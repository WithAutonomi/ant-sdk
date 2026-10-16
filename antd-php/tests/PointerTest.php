<?php

declare(strict_types=1);

namespace Autonomi\Antd\Tests;

use Autonomi\Antd\AntdClient;
use Autonomi\Antd\Errors\AlreadyExistsError;
use Autonomi\Antd\Errors\AntdError;
use Autonomi\Antd\Errors\BadRequestError;
use Autonomi\Antd\Errors\CloseGroupShortfallError;
use Autonomi\Antd\Errors\ConflictError;
use Autonomi\Antd\Errors\ErrorFactory;
use Autonomi\Antd\Errors\ForkError;
use Autonomi\Antd\Errors\InternalError;
use Autonomi\Antd\Errors\NotFoundError;
use Autonomi\Antd\Errors\PointerFinalError;
use Autonomi\Antd\Errors\ServiceUnavailableError;
use Autonomi\Antd\Models\PointerCounter;
use Autonomi\Antd\Models\PointerFinalityStatus;
use Autonomi\Antd\Models\PointerOp;
use Autonomi\Antd\Models\PointerPrepareRequest;
use Autonomi\Antd\Models\PointerTargetKind;
use GuzzleHttp\Client;
use GuzzleHttp\Handler\MockHandler;
use GuzzleHttp\HandlerStack;
use GuzzleHttp\Middleware;
use GuzzleHttp\Psr7\Response;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;
use Psr\Http\Message\RequestInterface;

/**
 * The pointer API over a mocked daemon (Guzzle MockHandler): request shapes,
 * response parsing, counters up to 2^64 - 1, and the error-code mapping.
 */
class PointerTest extends TestCase
{
    /** @var list<array{request: RequestInterface}> */
    private array $history = [];

    private function client(Response ...$responses): AntdClient
    {
        $stack = HandlerStack::create(new MockHandler($responses));
        $stack->push(Middleware::history($this->history));
        return new AntdClient('http://localhost:8082', 300.0, new Client(['handler' => $stack]));
    }

    /** @param array<mixed> $body */
    private function json(int $status, array $body): Response
    {
        return new Response($status, ['Content-Type' => 'application/json'], (string) json_encode($body));
    }

    private function raw(int $status, string $json): Response
    {
        return new Response($status, ['Content-Type' => 'application/json'], $json);
    }

    private function lastRequest(): RequestInterface
    {
        $this->assertNotEmpty($this->history, 'no request was sent');
        return $this->history[count($this->history) - 1]['request'];
    }

    /** @return array<mixed> */
    private function lastBody(): array
    {
        $body = json_decode((string) $this->lastRequest()->getBody(), true);
        $this->assertIsArray($body);
        return $body;
    }

    private function catchAntdError(callable $call): AntdError
    {
        try {
            $call();
        } catch (AntdError $e) {
            return $e;
        }
        $this->fail('Expected an AntdError');
    }

    // --- Keys ---

    public function testPointerKeys(): void
    {
        $client = $this->client($this->json(200, ['keys' => [['address' => 'aa'], ['address' => 'bb'], ['nope' => 1]]]));
        $this->assertSame(['aa', 'bb'], $client->pointerKeys());
        $this->assertSame('GET', $this->lastRequest()->getMethod());
        $this->assertSame('/v1/pointers/keys', $this->lastRequest()->getUri()->getPath());
    }

    public function testPointerKeysEmpty(): void
    {
        $client = $this->client($this->json(200, ['keys' => []]));
        $this->assertSame([], $client->pointerKeys());
    }

    // --- Writes ---

    public function testCreateSendsOwnerAndTargetAndLeavesKindToTheDaemon(): void
    {
        $client = $this->client($this->json(200, ['address' => 'aa', 'state_id' => 'ss', 'counter' => '0']));
        $w = $client->pointerCreate('aa', 'tt');
        $this->assertSame(['aa', 'ss', '0'], [$w->address, $w->stateId, $w->counter]);
        $this->assertSame('POST', $this->lastRequest()->getMethod());
        $this->assertSame('/v1/pointers', $this->lastRequest()->getUri()->getPath());
        $this->assertSame(['owner' => 'aa', 'target' => 'tt'], $this->lastBody());
    }

    public function testUpdateSendsKind(): void
    {
        $client = $this->client($this->json(200, ['address' => 'aa', 'state_id' => 'ss', 'counter' => '7']));
        $w = $client->pointerUpdate('aa', 'bb', PointerTargetKind::Pointer);
        $this->assertSame('7', $w->counter);
        $this->assertSame('/v1/pointers/update', $this->lastRequest()->getUri()->getPath());
        $this->assertSame(['owner' => 'aa', 'target' => 'bb', 'kind' => 'pointer'], $this->lastBody());
    }

    public function testUpdateAsync(): void
    {
        $client = $this->client($this->json(200, ['address' => 'aa', 'state_id' => 'ss', 'counter' => '2']));
        $w = $client->pointerUpdateAsync('aa', 'tt', PointerTargetKind::Chunk)->wait();
        $this->assertSame('2', $w->counter);
        $this->assertSame(['owner' => 'aa', 'target' => 'tt', 'kind' => 'chunk'], $this->lastBody());
    }

    public function testTransferKeepsAFailedFinalityCheck(): void
    {
        $client = $this->client($this->json(200, [
            'address' => 'aa', 'state_id' => 'ss', 'finality' => null, 'finality_error' => 'only 3 answered',
        ]));
        $t = $client->pointerTransfer('aa', 'bb');
        $this->assertNull($t->finality);
        $this->assertSame('only 3 answered', $t->finalityError);
        $this->assertSame(['aa', 'ss'], [$t->address, $t->stateId]);
        $this->assertSame('/v1/pointers/transfer', $this->lastRequest()->getUri()->getPath());
        $this->assertSame(['owner' => 'aa', 'recipient' => 'bb'], $this->lastBody());
    }

    public function testTransferParsesFinality(): void
    {
        $client = $this->client($this->json(200, [
            'address' => 'aa', 'state_id' => 'ss',
            'finality' => [
                'address' => 'aa', 'group' => 7, 'answered' => 7, 'status' => 'final', 'counter' => null,
                'state' => ['state_id' => 'ss', 'kind' => 'pointer', 'kind_tag' => 1, 'target' => 'bb', 'holders' => 7, 'transferred_to' => 'bb'],
                'states' => [], 'majority' => null, 'transferred_to' => 'bb',
            ],
        ]));
        $t = $client->pointerTransfer('aa', 'bb');
        $this->assertNotNull($t->finality);
        $this->assertTrue($t->finality->isFinal());
        $this->assertSame('bb', $t->finality->transferredTo);
        $this->assertSame(7, $t->finality->state?->holders);
        $this->assertNull($t->finalityError);
    }

    // --- Reads ---

    public function testGetReadsTheFinalCounterExactly(): void
    {
        $client = $this->client($this->raw(200, '{"address":"aa","owner":"pk","counter":"18446744073709551615",'
            . '"kind":"pointer","kind_tag":1,"target":"bb","state_id":"ss","is_final":true,"transferred_to":"bb"}'));
        $r = $client->pointerGet('aa');
        $this->assertSame(PointerCounter::FINAL, $r->counter);
        $this->assertSame('18446744073709551615', $r->counter);
        $this->assertTrue($r->isFinal);
        $this->assertSame('bb', $r->transferredTo);
        $this->assertSame(1, $r->kindTag);
        $this->assertSame(PointerTargetKind::Pointer, $r->targetKind());
        $this->assertSame(['aa', 'pk', 'pointer', 'bb', 'ss'], [$r->address, $r->owner, $r->kind, $r->target, $r->stateId]);
        $this->assertSame('/v1/pointers/aa', $this->lastRequest()->getUri()->getPath());
    }

    public function testGetMapsNullAndEmptyTransferredToToNull(): void
    {
        $body = ['address' => 'aa', 'owner' => 'pk', 'counter' => '3', 'kind' => 'chunk', 'kind_tag' => 0,
            'target' => 'tt', 'state_id' => 'ss', 'is_final' => false];
        $client = $this->client(
            $this->json(200, $body + ['transferred_to' => null]),
            $this->json(200, $body + ['transferred_to' => '']),
            $this->json(200, $body),
        );
        foreach ([1, 2, 3] as $_) {
            $r = $client->pointerGet('aa');
            $this->assertNull($r->transferredTo);
            $this->assertFalse($r->isFinal);
            $this->assertSame(PointerTargetKind::Chunk, $r->targetKind());
        }
    }

    public function testGetAsync(): void
    {
        $client = $this->client($this->json(200, ['address' => 'aa', 'counter' => '5', 'kind_tag' => 0]));
        $r = $client->pointerGetAsync('aa')->wait();
        $this->assertSame('5', $r->counter);
    }

    public function testGetMissingKindTagIsNotAChunk(): void
    {
        $client = $this->client($this->json(200, ['address' => 'aa', 'counter' => '0']));
        $r = $client->pointerGet('aa');
        $this->assertSame(255, $r->kindTag);
        $this->assertNull($r->targetKind());
    }

    public function testGetNotFound(): void
    {
        $client = $this->client($this->json(404, ['error' => 'no pointer at aa', 'code' => 'NOT_FOUND']));
        $this->assertInstanceOf(NotFoundError::class, $this->catchAntdError(fn() => $client->pointerGet('aa')));
    }

    public function testAddressIsPathEncoded(): void
    {
        $client = $this->client($this->json(200, ['kind' => 'chunk', 'kind_tag' => 0, 'target' => 'tt']));
        $client->pointerResolve('a/b');
        $this->assertSame('/v1/pointers/a%2Fb/resolve', $this->lastRequest()->getUri()->getPath());
    }

    /** @return array<string, array{string}> Counter literals that are not a decimal u64 string. */
    public static function malformedCounterProvider(): array
    {
        return [
            'json number' => ['3'],
            'null' => ['null'],
            'bool' => ['true'],
            'empty' => ['""'],
            'negative' => ['"-1"'],
            'plus sign' => ['"+1"'],
            'fraction' => ['"1.5"'],
            'exponent' => ['"1e3"'],
            'hex' => ['"0x1"'],
            'leading space' => ['" 1"'],
            'trailing newline' => ['"1\n"'],
            'one past u64' => ['"18446744073709551616"'],
            'far past u64' => ['"99999999999999999999"'],
            'twenty-one digits' => ['"100000000000000000000"'],
            'array' => ['["1"]'],
        ];
    }

    #[DataProvider('malformedCounterProvider')]
    public function testMalformedCounterIsAnError(string $literal): void
    {
        $client = $this->client($this->raw(200, '{"address":"aa","counter":' . $literal . '}'));
        $this->expectException(\UnexpectedValueException::class);
        $client->pointerGet('aa');
    }

    public function testMissingCounterIsAnError(): void
    {
        $client = $this->client($this->json(200, ['address' => 'aa', 'state_id' => 'ss']));
        $this->expectException(\UnexpectedValueException::class);
        $client->pointerCreate('aa', 'tt');
    }

    public function testCounterIsCanonicalised(): void
    {
        $this->assertSame('7', PointerCounter::parse('007'));
        $this->assertSame('0', PointerCounter::parse('0'));
        $this->assertSame('0', PointerCounter::parse('000'));
        $this->assertSame(PointerCounter::FINAL, PointerCounter::parse('0018446744073709551615'));
        $this->assertSame('9223372036854775808', PointerCounter::parse('9223372036854775808'));
    }

    public function testResolveAndController(): void
    {
        $client = $this->client(
            $this->json(200, ['kind' => 'unknown', 'kind_tag' => 42, 'target' => 'tt']),
            $this->json(200, ['pointer' => 'cc', 'transfers' => ['bb', 'cc'], 'frozen' => false]),
        );
        $res = $client->pointerResolve('aa');
        $this->assertSame(['unknown', 42, 'tt'], [$res->kind, $res->kindTag, $res->target]);
        $this->assertNull($res->targetKind());
        $this->assertSame('/v1/pointers/aa/resolve', $this->lastRequest()->getUri()->getPath());

        $ctl = $client->pointerController('aa');
        $this->assertSame('cc', $ctl->pointer);
        $this->assertSame(['bb', 'cc'], $ctl->transfers);
        $this->assertFalse($ctl->frozen);
        $this->assertSame('/v1/pointers/aa/controller', $this->lastRequest()->getUri()->getPath());
    }

    public function testControllerFrozenAsync(): void
    {
        $client = $this->client($this->json(200, ['pointer' => 'aa', 'transfers' => [], 'frozen' => true]));
        $ctl = $client->pointerControllerAsync('aa')->wait();
        $this->assertTrue($ctl->frozen);
        $this->assertSame([], $ctl->transfers);
    }

    public function testFinalityOpen(): void
    {
        $client = $this->client($this->json(200, [
            'address' => 'aa', 'group' => 7, 'answered' => 7, 'status' => 'open', 'counter' => '3',
            'state' => null, 'states' => [], 'majority' => null, 'transferred_to' => null,
        ]));
        $f = $client->pointerFinality('aa');
        $this->assertSame(PointerFinalityStatus::Open, $f->status);
        $this->assertSame('open', $f->rawStatus);
        $this->assertSame('3', $f->counter);
        $this->assertSame([7, 7], [$f->group, $f->answered]);
        $this->assertNull($f->state);
        $this->assertNull($f->majority);
        $this->assertNull($f->transferredTo);
        $this->assertSame([], $f->states);
        $this->assertFalse($f->isFinal());
        $this->assertSame('/v1/pointers/aa/finality', $this->lastRequest()->getUri()->getPath());
    }

    public function testFinalityForked(): void
    {
        $client = $this->client($this->json(200, [
            'address' => 'bb', 'group' => 7, 'answered' => 6, 'status' => 'forked', 'counter' => null,
            'states' => [
                ['state_id' => 's1', 'kind' => 'pointer', 'kind_tag' => 1, 'target' => 't1', 'holders' => 4, 'transferred_to' => 't1'],
                ['state_id' => 's2', 'kind' => 'chunk', 'kind_tag' => 0, 'target' => 't2', 'holders' => 2, 'transferred_to' => null],
            ],
            'majority' => ['state_id' => 's1', 'kind' => 'pointer', 'kind_tag' => 1, 'target' => 't1', 'holders' => 4, 'transferred_to' => 't1'],
            'transferred_to' => null,
        ]));
        $f = $client->pointerFinalityAsync('bb')->wait();
        $this->assertSame(PointerFinalityStatus::Forked, $f->status);
        $this->assertNull($f->counter);
        $this->assertCount(2, $f->states);
        $this->assertSame('t1', $f->states[0]->transferredTo);
        $this->assertNull($f->states[1]->transferredTo);
        $this->assertSame(4, $f->majority?->holders);
        $this->assertSame('s1', $f->majority?->stateId);
    }

    public function testFinalityUnknownStatusKeepsTheWireString(): void
    {
        $client = $this->client($this->json(200, ['address' => 'aa', 'group' => 7, 'answered' => 7, 'status' => 'quantum']));
        $f = $client->pointerFinality('aa');
        $this->assertSame(PointerFinalityStatus::Unknown, $f->status);
        $this->assertSame('quantum', $f->rawStatus);
        $this->assertNull($f->counter);
    }

    public function testFinalityEmptyCounterIsUnset(): void
    {
        $client = $this->client($this->json(200, ['address' => 'aa', 'status' => 'settling', 'counter' => '']));
        $this->assertNull($client->pointerFinality('aa')->counter);
    }

    public function testFinalityNumericCounterIsAnError(): void
    {
        $client = $this->client($this->raw(200, '{"address":"aa","status":"open","counter":3}'));
        $this->expectException(\UnexpectedValueException::class);
        $client->pointerFinality('aa');
    }

    public function testFinalityStatusWireValues(): void
    {
        $this->assertSame(PointerFinalityStatus::Open, PointerFinalityStatus::fromWire('open'));
        $this->assertSame(PointerFinalityStatus::Settling, PointerFinalityStatus::fromWire('settling'));
        $this->assertSame(PointerFinalityStatus::Unconfirmed, PointerFinalityStatus::fromWire('unconfirmed'));
        $this->assertSame(PointerFinalityStatus::Final, PointerFinalityStatus::fromWire('final'));
        $this->assertSame(PointerFinalityStatus::Forked, PointerFinalityStatus::fromWire('forked'));
        $this->assertSame(PointerFinalityStatus::Unknown, PointerFinalityStatus::fromWire(''));
        $this->assertSame(PointerFinalityStatus::Unknown, PointerFinalityStatus::fromWire('FINAL'));
    }

    // --- External signer ---

    public function testPrepareTransferAndFinalize(): void
    {
        $client = $this->client(
            $this->json(200, [
                'upload_id' => 'up', 'op' => 'transfer', 'address' => 'aa', 'state_id' => 'ss',
                'counter' => '18446744073709551615', 'payment_type' => 'wave_batch',
                'payments' => [['quote_hash' => '0xq', 'rewards_address' => '0xr', 'amount' => '5']],
                'total_amount' => '5', 'payment_vault_address' => '0xv', 'payment_token_address' => '0xt',
                'rpc_url' => 'http://rpc',
            ]),
            $this->json(200, [
                'address' => 'aa', 'state_id' => 'ss', 'counter' => '18446744073709551615',
                'finality' => [
                    'address' => 'aa', 'group' => 7, 'answered' => 7, 'status' => 'final',
                    'state' => ['state_id' => 'ss', 'kind' => 'pointer', 'kind_tag' => 1, 'target' => 'bb', 'holders' => 7, 'transferred_to' => 'bb'],
                    'states' => [], 'transferred_to' => 'bb',
                ],
            ]),
        );

        $prep = $client->pointerPrepare(PointerPrepareRequest::transfer('aa', 'bb'));
        $this->assertSame('/v1/pointers/prepare', $this->lastRequest()->getUri()->getPath());
        $this->assertSame(['owner' => 'aa', 'op' => 'transfer', 'recipient' => 'bb'], $this->lastBody());
        $this->assertSame('up', $prep->uploadId);
        $this->assertSame('transfer', $prep->op);
        $this->assertSame(PointerCounter::FINAL, $prep->counter);
        $this->assertSame('wave_batch', $prep->paymentType);
        $this->assertCount(1, $prep->payments);
        $this->assertSame(['0xq', '0xr', '5'], [$prep->payments[0]->quoteHash, $prep->payments[0]->rewardsAddress, $prep->payments[0]->amount]);
        $this->assertSame(['5', '0xv', '0xt', 'http://rpc'], [$prep->totalAmount, $prep->paymentVaultAddress, $prep->paymentTokenAddress, $prep->rpcUrl]);

        $fin = $client->pointerFinalize('up', ['0xq' => '0xtx']);
        $this->assertSame('/v1/pointers/finalize', $this->lastRequest()->getUri()->getPath());
        $this->assertSame(['upload_id' => 'up', 'tx_hashes' => ['0xq' => '0xtx']], $this->lastBody());
        $this->assertSame(PointerCounter::FINAL, $fin->counter);
        $this->assertNotNull($fin->finality);
        $this->assertTrue($fin->finality->isFinal());
        $this->assertSame('bb', $fin->finality->transferredTo);
    }

    public function testPrepareCreateAndUpdateSendTargetAndKind(): void
    {
        $prepared = ['upload_id' => 'up', 'op' => 'update', 'address' => 'aa', 'state_id' => 'ss', 'counter' => '1',
            'payment_type' => 'wave_batch', 'payments' => [], 'total_amount' => '0',
            'payment_vault_address' => '', 'payment_token_address' => '', 'rpc_url' => ''];
        $client = $this->client($this->json(200, $prepared), $this->json(200, $prepared));

        $client->pointerPrepare(PointerPrepareRequest::create('aa', 'tt'));
        $this->assertSame(['owner' => 'aa', 'op' => 'create', 'target' => 'tt'], $this->lastBody());

        $prep = $client->pointerPrepareAsync(PointerPrepareRequest::update('aa', 'tt', PointerTargetKind::Pointer))->wait();
        $this->assertSame(['owner' => 'aa', 'op' => 'update', 'target' => 'tt', 'kind' => 'pointer'], $this->lastBody());
        $this->assertSame('1', $prep->counter);
        $this->assertSame([], $prep->payments);
    }

    public function testPrepareRequestFactories(): void
    {
        $t = PointerPrepareRequest::transfer('aa', 'bb');
        $this->assertSame(PointerOp::Transfer, $t->op);
        $this->assertNull($t->target);
        $c = PointerPrepareRequest::create('aa', 'tt', PointerTargetKind::Chunk);
        $this->assertSame(PointerOp::Create, $c->op);
        $this->assertSame(['owner' => 'aa', 'op' => 'create', 'target' => 'tt', 'kind' => 'chunk'], $c->toArray());
    }

    public function testFinalizeWithoutHashesSendsAnEmptyObject(): void
    {
        $client = $this->client($this->json(400, ['error' => 'missing tx hash', 'code' => 'BAD_REQUEST']));
        $e = $this->catchAntdError(fn() => $client->pointerFinalize('up', []));
        $this->assertInstanceOf(BadRequestError::class, $e);
        $this->assertSame('{"upload_id":"up","tx_hashes":{}}', (string) $this->lastRequest()->getBody());
    }

    // --- Errors ---

    /** @return array<string, array{int, string, class-string<AntdError>}> */
    public static function pointerErrorProvider(): array
    {
        return [
            'POINTER_FINAL' => [409, '{"error":"x","code":"POINTER_FINAL"}', PointerFinalError::class],
            'POINTER_FORKED' => [409, '{"error":"x","code":"POINTER_FORKED"}', ForkError::class],
            'CONFLICT' => [409, '{"error":"x","code":"CONFLICT"}', ConflictError::class],
            'ALREADY_EXISTS' => [409, '{"error":"x","code":"ALREADY_EXISTS"}', AlreadyExistsError::class],
            'plain 409' => [409, '{"error":"x"}', AlreadyExistsError::class],
            'CLOSE_GROUP_SHORTFALL' => [503, '{"error":"x","code":"CLOSE_GROUP_SHORTFALL"}', CloseGroupShortfallError::class],
            'SERVICE_UNAVAILABLE' => [503, '{"error":"x","code":"SERVICE_UNAVAILABLE"}', ServiceUnavailableError::class],
            'unknown owner' => [400, '{"error":"no key for owner","code":"BAD_REQUEST"}', BadRequestError::class],
            'non-string code' => [409, '{"error":"x","code":["POINTER_FINAL"]}', AlreadyExistsError::class],
        ];
    }

    /** @param class-string<AntdError> $class */
    #[DataProvider('pointerErrorProvider')]
    public function testErrorsMapByCode(int $status, string $json, string $class): void
    {
        $client = $this->client($this->raw($status, $json));
        $e = $this->catchAntdError(fn() => $client->pointerUpdate('aa', 'tt'));
        $this->assertSame($class, get_class($e));
        $this->assertSame($status, $e->statusCode);
        $this->assertStringContainsString(json_decode($json, true)['error'], $e->getMessage());
    }

    public function testPointerConflictsDoNotFoldIntoAlreadyExists(): void
    {
        foreach (['POINTER_FINAL', 'POINTER_FORKED', 'CONFLICT'] as $code) {
            $e = ErrorFactory::fromResponse(409, 'x', ['error' => 'x', 'code' => $code]);
            $this->assertNotInstanceOf(AlreadyExistsError::class, $e, $code);
        }
        $shortfall = ErrorFactory::fromResponse(503, 'x', ['code' => 'CLOSE_GROUP_SHORTFALL']);
        $this->assertNotInstanceOf(ServiceUnavailableError::class, $shortfall);
        $this->assertNotInstanceOf(InternalError::class, $shortfall);
    }

    /** @return array<string, array{string, bool}> retryable literal => expected flag */
    public static function shortfallRetryableProvider(): array
    {
        return [
            'true' => [',"retryable":true', true],
            'false' => [',"retryable":false', false],
            'absent' => ['', false],
            'null' => [',"retryable":null', false],
            'string' => [',"retryable":"true"', false],
            'number' => [',"retryable":1', false],
        ];
    }

    #[DataProvider('shortfallRetryableProvider')]
    public function testCloseGroupShortfallRetryable(string $member, bool $retryable): void
    {
        $client = $this->client($this->raw(503, '{"error":"only 3 of 7 stored","code":"CLOSE_GROUP_SHORTFALL"' . $member . '}'));
        $e = $this->catchAntdError(fn() => $client->pointerFinalize('up', ['0xq' => '0xtx']));
        $this->assertInstanceOf(CloseGroupShortfallError::class, $e);
        $this->assertSame($retryable, $e->retryable);
        $this->assertSame(503, $e->statusCode);
    }

    public function testAsyncWriteRejectsWithTypedError(): void
    {
        $client = $this->client($this->raw(409, '{"error":"prepared write pending","code":"CONFLICT"}'));
        try {
            $client->pointerCreateAsync('aa', 'tt')->wait();
            $this->fail('Expected a ConflictError');
        } catch (ConflictError $e) {
            $this->assertSame(409, $e->statusCode);
        }
    }

    /**
     * Paid writes are never retried by the client: one failed attempt is one
     * request. The mock holds a single response, so a retry would run it dry
     * and fail with an OutOfBoundsException instead of the typed error.
     */
    public function testPaidWritesAreNotRetried(): void
    {
        $shortfall = '{"error":"only 3 of 7 stored","code":"CLOSE_GROUP_SHORTFALL","retryable":true}';
        $calls = [
            'create' => fn(AntdClient $c) => $c->pointerCreate('aa', 'tt'),
            'update' => fn(AntdClient $c) => $c->pointerUpdate('aa', 'tt'),
            'transfer' => fn(AntdClient $c) => $c->pointerTransfer('aa', 'bb'),
            'finalize' => fn(AntdClient $c) => $c->pointerFinalize('up', ['0xq' => '0xtx']),
            'create async' => fn(AntdClient $c) => $c->pointerCreateAsync('aa', 'tt')->wait(),
            'finalize async' => fn(AntdClient $c) => $c->pointerFinalizeAsync('up', ['0xq' => '0xtx'])->wait(),
        ];
        foreach ($calls as $name => $call) {
            $this->history = [];
            $client = $this->client($this->raw(503, $shortfall));
            $e = $this->catchAntdError(fn() => $call($client));
            $this->assertInstanceOf(CloseGroupShortfallError::class, $e, $name);
            $this->assertCount(1, $this->history, $name);
        }
    }
}
