#[[
This source file is part of the FlyingFox open source project

Copyright (c) 2024 Simon Whitty and the FlyingFox project authors
Licensed under MIT License

See https://github.com/swhitty/FlyingFox/blob/main/LICENSE for license information
#]]

file(GLOB_RECURSE FLYING_FOX_SOURCES CONFIGURE_DEPENDS *.swift)

add_library(FlyingFox ${FLYING_FOX_SOURCES})
target_link_libraries(FlyingFox PUBLIC FlyingSocks)

target_compile_options(FlyingFox PRIVATE
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-package-name FlyingFox>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-upcoming-feature ExistentialAny>"
  "$<$<COMPILE_LANGUAGE:Swift>:-swift-version;6>")

get_swift_host_os(_swift_os)
set_target_properties(FlyingFox PROPERTIES
  SOVERSION 0
  INTERFACE_INCLUDE_DIRECTORIES
    "$<BUILD_INTERFACE:${CMAKE_Swift_MODULE_DIRECTORY}>;$<INSTALL_INTERFACE:${CMAKE_INSTALL_LIBDIR}/swift/${_swift_os}>")

_install_target(FlyingFox)
set_property(GLOBAL APPEND PROPERTY FLYING_FOX_EXPORTS FlyingFox)
