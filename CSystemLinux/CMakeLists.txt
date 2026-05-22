#[[
This source file is part of the FlyingFox open source project

Copyright (c) 2024 Simon Whitty and the FlyingFox project authors
Licensed under MIT License

See https://github.com/swhitty/FlyingFox/blob/main/LICENSE for license information
#]]

# C interop shim used on Linux/Android: exposes a `CSystemLinux` Swift module
# containing the libc bits FlyingSocks needs for socket I/O.
add_library(CSystemLinux INTERFACE)
target_include_directories(CSystemLinux INTERFACE
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/CSystemLinux>)

install(FILES
  include/CSystemLinux.h
  include/module.modulemap
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/CSystemLinux)

_install_target(CSystemLinux)
set_property(GLOBAL APPEND PROPERTY FLYING_FOX_EXPORTS CSystemLinux)
