#[[
This source file is part of the FlyingFox open source project

Copyright (c) 2024 Simon Whitty and the FlyingFox project authors
Licensed under MIT License

See https://github.com/swhitty/FlyingFox/blob/main/LICENSE for license information
#]]

include(CMakePackageConfigHelpers)

set(FLYING_FOX_EXPORTS_FILE
  ${CMAKE_CURRENT_BINARY_DIR}/FlyingFoxExports.cmake)

configure_file(FlyingFoxConfig.cmake.in
  ${CMAKE_CURRENT_BINARY_DIR}/FlyingFoxConfig.cmake)

get_property(FLYING_FOX_EXPORTS GLOBAL PROPERTY FLYING_FOX_EXPORTS)
export(TARGETS ${FLYING_FOX_EXPORTS}
  NAMESPACE FlyingFox::
  FILE ${FLYING_FOX_EXPORTS_FILE}
  EXPORT_LINK_INTERFACE_LIBRARIES)

install(EXPORT FlyingFoxTargets
  FILE FlyingFoxTargets.cmake
  NAMESPACE FlyingFox::
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/FlyingFox)

configure_package_config_file(
  FlyingFoxConfig.cmake.in
  ${CMAKE_CURRENT_BINARY_DIR}/install/FlyingFoxConfig.cmake
  INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/FlyingFox)

install(FILES
  ${CMAKE_CURRENT_BINARY_DIR}/install/FlyingFoxConfig.cmake
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/FlyingFox)
