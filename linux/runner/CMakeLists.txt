cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

pkg_check_modules(MPV REQUIRED IMPORTED_TARGET mpv)
pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)

add_executable(${BINARY_NAME}
  "gl_platform.cc"
  "main.cc"
  "my_application.cc"
  "native_window.cc"
  "trailer_texture.cc"
  "video_host.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

apply_standard_settings(${BINARY_NAME})
target_compile_features(${BINARY_NAME} PUBLIC cxx_std_17)

add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK PkgConfig::MPV PkgConfig::EPOXY)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
