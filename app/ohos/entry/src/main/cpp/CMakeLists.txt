cmake_minimum_required(VERSION 3.5.0)
project(fqplayer)
set(CMAKE_CXX_STANDARD 17)
add_library(ijkplayer SHARED IMPORTED)
set_target_properties(ijkplayer PROPERTIES IMPORTED_LOCATION
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../oh_modules/@ohos/ijkplayer/libs/${OHOS_ARCH}/libijkplayer.so")
add_library(ijksdl SHARED IMPORTED)
set_target_properties(ijksdl PROPERTIES IMPORTED_LOCATION
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../oh_modules/@ohos/ijkplayer/libs/${OHOS_ARCH}/libijksdl.so")
add_library(fqplayer SHARED fqplayer.cpp software_video_output.cpp)
target_link_libraries(fqplayer PUBLIC ijkplayer ijksdl libace_napi.z.so libnative_window.so libnative_buffer.so libhilog_ndk.z.so)
