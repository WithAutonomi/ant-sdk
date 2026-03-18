cmake_minimum_required(VERSION 3.14)
project(antd-cpp VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# --- Dependencies via FetchContent ---
include(FetchContent)

FetchContent_Declare(
    nlohmann_json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG        v3.11.3
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(nlohmann_json)

FetchContent_Declare(
    httplib
    GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
    GIT_TAG        v0.18.3
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(httplib)

# --- Library target ---
add_library(antd
    src/client.cpp
    src/async_client.cpp
    src/base64.cpp
)

target_include_directories(antd
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(antd
    PUBLIC
        nlohmann_json::nlohmann_json
        httplib::httplib
)

# --- Examples ---
option(ANTD_BUILD_EXAMPLES "Build example programs" ON)
if(ANTD_BUILD_EXAMPLES)
    foreach(example
        01-connect
        02-data
        03-chunks
        04-files
        05-graph
        06-private-data
    )
        add_executable(${example} examples/${example}.cpp)
        target_link_libraries(${example} PRIVATE antd)
    endforeach()
endif()

# --- Tests ---
option(ANTD_BUILD_TESTS "Build tests" ON)
if(ANTD_BUILD_TESTS)
    enable_testing()

    FetchContent_Declare(
        doctest
        GIT_REPOSITORY https://github.com/doctest/doctest.git
        GIT_TAG        v2.4.11
        GIT_SHALLOW    TRUE
    )
    FetchContent_MakeAvailable(doctest)

    add_executable(antd_tests tests/test_client.cpp)
    target_link_libraries(antd_tests PRIVATE antd doctest::doctest)
    # Give tests access to internal base64 header
    target_include_directories(antd_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

    add_test(NAME antd_tests COMMAND antd_tests)
endif()
