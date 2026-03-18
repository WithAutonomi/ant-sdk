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

# --- Library target (REST) ---
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

# --- gRPC transport (optional) ---
#
# Enable with: cmake -B build -DANTD_BUILD_GRPC=ON
# Requires protoc and grpc_cpp_plugin on PATH, or a local gRPC install.
#
option(ANTD_BUILD_GRPC "Build gRPC client (requires gRPC and Protobuf)" OFF)
if(ANTD_BUILD_GRPC)
    find_package(Protobuf REQUIRED)
    find_package(gRPC REQUIRED)

    # Proto source directory
    set(ANTD_PROTO_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../antd/proto")

    # Collect all .proto files
    file(GLOB ANTD_PROTO_FILES "${ANTD_PROTO_DIR}/antd/v1/*.proto")

    # Output directory for generated code
    set(ANTD_PROTO_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/proto-gen")
    file(MAKE_DIRECTORY ${ANTD_PROTO_GEN_DIR})

    # Generate C++ sources from .proto files
    set(ANTD_PROTO_SRCS "")
    set(ANTD_PROTO_HDRS "")
    set(ANTD_GRPC_SRCS "")
    set(ANTD_GRPC_HDRS "")

    foreach(proto_file ${ANTD_PROTO_FILES})
        get_filename_component(proto_name ${proto_file} NAME_WE)
        list(APPEND ANTD_PROTO_SRCS "${ANTD_PROTO_GEN_DIR}/antd/v1/${proto_name}.pb.cc")
        list(APPEND ANTD_PROTO_HDRS "${ANTD_PROTO_GEN_DIR}/antd/v1/${proto_name}.pb.h")
        list(APPEND ANTD_GRPC_SRCS "${ANTD_PROTO_GEN_DIR}/antd/v1/${proto_name}.grpc.pb.cc")
        list(APPEND ANTD_GRPC_HDRS "${ANTD_PROTO_GEN_DIR}/antd/v1/${proto_name}.grpc.pb.h")
    endforeach()

    find_program(GRPC_CPP_PLUGIN grpc_cpp_plugin)

    add_custom_command(
        OUTPUT ${ANTD_PROTO_SRCS} ${ANTD_PROTO_HDRS} ${ANTD_GRPC_SRCS} ${ANTD_GRPC_HDRS}
        COMMAND ${Protobuf_PROTOC_EXECUTABLE}
            --proto_path=${ANTD_PROTO_DIR}
            --cpp_out=${ANTD_PROTO_GEN_DIR}
            --grpc_out=${ANTD_PROTO_GEN_DIR}
            --plugin=protoc-gen-grpc=${GRPC_CPP_PLUGIN}
            ${ANTD_PROTO_FILES}
        DEPENDS ${ANTD_PROTO_FILES}
        COMMENT "Generating C++ protobuf/gRPC sources"
    )

    add_library(antd_grpc
        src/grpc_client.cpp
        ${ANTD_PROTO_SRCS}
        ${ANTD_GRPC_SRCS}
    )

    target_include_directories(antd_grpc
        PUBLIC
            $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
            $<BUILD_INTERFACE:${ANTD_PROTO_GEN_DIR}>
            $<INSTALL_INTERFACE:include>
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    target_link_libraries(antd_grpc
        PUBLIC
            gRPC::grpc++
            protobuf::libprotobuf
    )
endif()

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

    # gRPC client tests — error mapping and model construction.
    # Does NOT require gRPC libraries; tests the mapping logic in isolation.
    add_executable(antd_grpc_tests tests/test_grpc_client.cpp)
    target_link_libraries(antd_grpc_tests PRIVATE doctest::doctest)
    target_include_directories(antd_grpc_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    )

    add_test(NAME antd_grpc_tests COMMAND antd_grpc_tests)
endif()
