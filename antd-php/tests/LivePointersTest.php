<?php

declare(strict_types=1);

namespace Autonomi\Antd\Tests;

use Autonomi\Antd\AntdClient;
use Autonomi\Antd\Errors\AlreadyExistsError;
use Autonomi\Antd\Errors\AntdError;
use Autonomi\Antd\Errors\BadRequestError;
use Autonomi\Antd\Errors\ConflictError;
use Autonomi\Antd\Errors\NotFoundError;
use Autonomi\Antd\Errors\PointerFinalError;
use Autonomi\Antd\Models\PointerCounter;
use Autonomi\Antd\Models\PointerFinalityStatus;
use Autonomi\Antd\Models\PointerPrepareRequest;
use Autonomi\Antd\Models\PointerTargetKind;
use PHPUnit\Framework\TestCase;

/**
 * Live pointer round trip against a running antd with a devnet behind it.
 *
 * Skipped unless both are set:
 *
 *  - `ANTD_TEST_URL` — the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
 *  - `ANTD_TEST_POINTER_OWNERS` — two comma-separated pointer addresses the
 *    daemon holds keys for (`antd --pointer-keys`) and that have **never been
 *    written**. The test creates both, transfers the first to the second, and
 *    leaves the second with a prepared write awaiting payment, so each pair
 *    can be used once.
 *
 * Every write is paid by the daemon's wallet, so run it against a devnet:
 *
 *     ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_POINTER_OWNERS=<hex>,<hex> \
 *         vendor/bin/phpunit tests/LivePointersTest.php
 */
class LivePointersTest extends TestCase
{
    private static function normalise(string $address): string
    {
        $address = strtolower(trim($address));
        return str_starts_with($address, '0x') ? substr($address, 2) : $address;
    }

    /** Run $call and return the AntdError it throws. */
    private function catchAntdError(callable $call): AntdError
    {
        try {
            $call();
        } catch (AntdError $e) {
            return $e;
        }
        $this->fail('Expected an AntdError');
    }

    public function testLivePointerRoundTrip(): void
    {
        $url = getenv('ANTD_TEST_URL');
        $owners = getenv('ANTD_TEST_POINTER_OWNERS');
        if (!is_string($url) || $url === '' || !is_string($owners) || !str_contains($owners, ',')) {
            $this->markTestSkipped('set ANTD_TEST_URL and ANTD_TEST_POINTER_OWNERS to run');
        }
        [$a, $b] = array_map(self::normalise(...), explode(',', $owners, 2));
        $client = new AntdClient($url, 300.0);

        // Both owners must be writable through this daemon.
        $keys = array_map(self::normalise(...), $client->pointerKeys());
        $this->assertContains($a, $keys, 'daemon holds no key for ' . $a);
        $this->assertContains($b, $keys, 'daemon holds no key for ' . $b);
        // A write for an owner the daemon holds no key for is refused, unpaid.
        $stranger = str_repeat('0', 64);
        $this->assertNotContains($stranger, $keys);
        $this->assertInstanceOf(
            BadRequestError::class,
            $this->catchAntdError(fn() => $client->pointerCreate($stranger, $stranger)),
        );

        // Real targets, so the chain can be followed back to bytes.
        $one = $client->dataPutPublic('antd-php pointer target one')->address;
        $two = $client->dataPutPublic('antd-php pointer target two')->address;

        // --- create, read, update ---
        $this->assertInstanceOf(
            NotFoundError::class,
            $this->catchAntdError(fn() => $client->pointerGet($a)),
            "owner {$a} has been written before; use a fresh pair",
        );
        $w = $client->pointerCreate($a, $one, PointerTargetKind::Chunk);
        $this->assertSame('0', $w->counter);
        $this->assertSame($a, $w->address);
        $this->assertInstanceOf(
            AlreadyExistsError::class,
            $this->catchAntdError(fn() => $client->pointerCreate($a, $two)),
        );
        $r = $client->pointerGet($a);
        $this->assertSame(['0', $one, false], [$r->counter, $r->target, $r->isFinal]);
        $this->assertSame(PointerTargetKind::Chunk, $r->targetKind());
        $this->assertSame(2 * 1952, strlen($r->owner));
        $this->assertNull($r->transferredTo);
        $res = $client->pointerResolve($a);
        $this->assertSame($one, $res->target);
        $this->assertSame('antd-php pointer target one', $client->dataGetPublic($res->target));

        $w = $client->pointerUpdate($a, $two);
        $this->assertSame('1', $w->counter);
        $this->assertSame($two, $client->pointerResolveAsync($a)->wait()->target);
        $f = $client->pointerFinality($a);
        $this->assertSame(PointerFinalityStatus::Open, $f->status);
        $this->assertSame('1', $f->counter);
        $this->assertSame($f->group, $f->answered);

        // --- a second pointer, written asynchronously ---
        $w = $client->pointerCreateAsync($b, $one)->wait();
        $this->assertSame('0', $w->counter);
        $r = $client->pointerGetAsync($b)->wait();
        $this->assertSame(['0', $one], [$r->counter, $r->target]);

        // --- transfer a -> b ---
        $t = $client->pointerTransfer($a, $b);
        $this->assertNotNull($t->finality, 'the close group should answer after the transfer: ' . $t->finalityError);
        $this->assertSame(PointerFinalityStatus::Final, $t->finality->status);
        $this->assertSame($b, $t->finality->transferredTo);
        $r = $client->pointerGet($a);
        $this->assertTrue($r->isFinal);
        $this->assertSame(PointerCounter::FINAL, $r->counter);
        $this->assertSame($b, $r->transferredTo);
        $c = $client->pointerController($a);
        $this->assertSame([$b, [$b], false], [$c->pointer, $c->transfers, $c->frozen]);
        // a now resolves through b.
        $this->assertSame($one, $client->pointerResolve($a)->target);
        $this->assertTrue($client->pointerFinality($a)->isFinal());

        // A final pointer refuses every write, before anything is paid.
        $this->assertInstanceOf(
            PointerFinalError::class,
            $this->catchAntdError(fn() => $client->pointerUpdate($a, $one)),
        );
        $this->assertInstanceOf(
            PointerFinalError::class,
            $this->catchAntdError(fn() => $client->pointerTransfer($a, $b)),
        );

        // --- external signer, up to the quote ---
        // Last: the prepared write blocks b's other writes until it expires.
        $p = $client->pointerPrepare(PointerPrepareRequest::update($b, $two, PointerTargetKind::Chunk));
        $this->assertSame(['update', '1'], [$p->op, $p->counter]);
        $this->assertSame('wave_batch', $p->paymentType);
        $this->assertNotEmpty($p->payments);
        $this->assertNotSame('', $p->uploadId);
        $this->assertInstanceOf(
            ConflictError::class,
            $this->catchAntdError(fn() => $client->pointerUpdate($b, $two)),
        );
        $this->assertInstanceOf(
            ConflictError::class,
            $this->catchAntdError(fn() => $client->pointerPrepare(PointerPrepareRequest::update($b, $two))),
        );
        // A finalize without the payment is refused and keeps the session.
        $this->assertInstanceOf(
            BadRequestError::class,
            $this->catchAntdError(fn() => $client->pointerFinalize($p->uploadId, [])),
        );
        $this->assertInstanceOf(
            ConflictError::class,
            $this->catchAntdError(fn() => $client->pointerUpdate($b, $two)),
        );
    }
}
