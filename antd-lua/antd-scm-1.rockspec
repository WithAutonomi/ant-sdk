package = "antd"
version = "scm-1"
source = {
    url = "git://github.com/WithAutonomi/ant-sdk.git",
    dir = "ant-sdk/antd-lua",
}
description = {
    summary = "Lua SDK for the antd daemon — gateway to the Autonomi network",
    detailed = [[
        A Lua client library for the antd daemon REST API.
        Provides access to the Autonomi decentralized network for storing
        and retrieving immutable data, chunks, and files.
    ]],
    homepage = "https://github.com/WithAutonomi/ant-sdk/tree/main/antd-lua",
    license = "MIT",
}
dependencies = {
    "lua >= 5.1",
    "luasocket >= 3.0",
    "lua-cjson >= 2.1",
}
build = {
    type = "builtin",
    modules = {
        ["antd"]          = "src/antd/init.lua",
        ["antd.client"]   = "src/antd/client.lua",
        ["antd.models"]   = "src/antd/models.lua",
        ["antd.errors"]   = "src/antd/errors.lua",
        ["antd.base64"]   = "src/antd/base64.lua",
        ["antd.discover"] = "src/antd/discover.lua",
    },
}
