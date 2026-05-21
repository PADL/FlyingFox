#[[
This source file is part of the FlyingFox open source project

Copyright (c) 2024 Simon Whitty and the FlyingFox project authors
Licensed under MIT License

See https://github.com/swhitty/FlyingFox/blob/main/LICENSE for license information
#]]

cmake_minimum_required(VERSION 3.16)
project(FlyingFox
  LANGUAGES Swift C)

list(APPEND CMAKE_MODULE_PATH ${PROJECT_SOURCE_DIR}/cmake/modules)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/swift)

if(CMAKE_SYSTEM_NAME STREQUAL Windows OR CMAKE_SYSTEM_NAME STREQUAL Darwin)
  option(BUILD_SHARED_LIBS "Build shared libraries by default" YES)
endif()

include(GNUInstallDirs)
include(SwiftSupport)

if(NOT (CMAKE_SYSTEM_NAME STREQUAL Darwin OR CMAKE_SYSTEM_NAME STREQUAL Windows))
  add_subdirectory(CSystemLinux)
endif()
add_subdirectory(FlyingSocks/Sources)
add_subdirectory(FlyingFox/Sources)
add_subdirectory(cmake/modules)
