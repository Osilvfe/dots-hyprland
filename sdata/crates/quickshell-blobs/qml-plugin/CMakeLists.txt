cmake_minimum_required(VERSION 3.20)
project(caelestia-blobs LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Quick Qml ShaderTools)

qt_add_library(caelestia-blobs SHARED
    blobgroup.cpp
    blobgroup.hpp
    blobshape.cpp
    blobshape.hpp
    blobrect.cpp
    blobrect.hpp
    blobinvertedrect.cpp
    blobinvertedrect.hpp
    blobmaterial.cpp
    blobmaterial.hpp
)

qt_add_qml_module(caelestia-blobs
    URI Caelestia.Blobs
    VERSION 1.0
)

# 链接 Rust 核心动力学库
find_library(RUST_BLOBS_LIB quickshell_blobs HINTS "${CMAKE_CURRENT_SOURCE_DIR}/../target/release")
if(RUST_BLOBS_LIB)
    target_link_libraries(caelestia-blobs PRIVATE ${RUST_BLOBS_LIB})
endif()

target_link_libraries(caelestia-blobs PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::Qml
)

qt_add_shaders(caelestia-blobs "blob_shaders"
    BATCHABLE OPTIMIZED NOHLSL NOMSL
    GLSL "300es,330"
    PREFIX "/"
    FILES
        shaders/blob.frag
        shaders/blob.vert
)
