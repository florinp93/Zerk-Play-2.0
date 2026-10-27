cmake_minimum_required(VERSION 3.22.1)
project(zerkac3 C)

set(AFTEN_DIR ${CMAKE_CURRENT_SOURCE_DIR}/aften)
add_library(zerkac3 SHARED
    zerk_ac3.c
    ${AFTEN_DIR}/libaften/a52enc.c
    ${AFTEN_DIR}/libaften/bitalloc.c
    ${AFTEN_DIR}/libaften/bitio.c
    ${AFTEN_DIR}/libaften/crc.c
    ${AFTEN_DIR}/libaften/dynrng.c
    ${AFTEN_DIR}/libaften/window.c
    ${AFTEN_DIR}/libaften/mdct.c
    ${AFTEN_DIR}/libaften/exponent.c
    ${AFTEN_DIR}/libaften/filter.c
    ${AFTEN_DIR}/libaften/util.c)
target_include_directories(zerkac3 PRIVATE ${AFTEN_DIR} ${AFTEN_DIR}/libaften)
target_compile_definitions(zerkac3 PRIVATE HAVE_CONFIG_H)
target_compile_options(zerkac3 PRIVATE -O2 -w)
target_link_libraries(zerkac3 m)
