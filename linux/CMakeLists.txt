# Project-level configuration.
cmake_minimum_required(VERSION 3.16)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "tsumiru")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "io.github.aaronbamblett.tsumiru" CACHE STRING "GTK application identifier")
if(DEFINED ENV{TSUMIRU_APPLICATION_ID} AND NOT "$ENV{TSUMIRU_APPLICATION_ID}" STREQUAL "")
  set(APPLICATION_ID "$ENV{TSUMIRU_APPLICATION_ID}")
endif()

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  # A bundled nlohmann/json in flutter_secure_storage_linux trips this
  # deprecation on newer clang (Fedora 42+); keep -Werror, just don't let this
  # one fail the build.
  target_compile_options(${TARGET} PRIVATE -Wno-error=deprecated-literal-operator)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(AVIF REQUIRED IMPORTED_TARGET libavif)
pkg_check_modules(GDKPIXBUF REQUIRED IMPORTED_TARGET gdk-pixbuf-2.0)
# Absolute libavif path roots the install-time dependency scan below.
find_library(TSUMIRU_AVIF_LIBRARY NAMES avif HINTS ${AVIF_LIBRARY_DIRS})
if(NOT "$ENV{TSUMIRU_BUNDLE_AVIF_DEPS}" STREQUAL "0" AND NOT TSUMIRU_AVIF_LIBRARY)
  message(FATAL_ERROR "libavif not found; cannot bundle the AVIF runtime closure")
endif()
get_filename_component(TSUMIRU_AVIF_LIB_DIR "${TSUMIRU_AVIF_LIBRARY}" DIRECTORY)

add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Define the application target. To change its name, change BINARY_NAME above,
# not the value here, or `flutter run` will no longer work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

# tsumiru_avif: app-owned AVIF-to-PNG shim loaded by the Dart worker.
add_library(tsumiru_avif SHARED
  "tsumiru_avif.cc"
  "tsumiru_avif.h"
)
apply_standard_settings(tsumiru_avif)
target_link_libraries(tsumiru_avif PRIVATE PkgConfig::AVIF PkgConfig::GDKPIXBUF)
# The shim resolves bundled siblings from its own directory ($ORIGIN).
set_target_properties(tsumiru_avif PROPERTIES
  INSTALL_RPATH "$ORIGIN"
  BUILD_WITH_INSTALL_RPATH TRUE
)

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

install(TARGETS tsumiru_avif
  LIBRARY DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Flatpak supplies these libraries; other bundles need the codec dependencies.
if(NOT "$ENV{TSUMIRU_BUNDLE_AVIF_DEPS}" STREQUAL "0")
  install(CODE "set(TSUMIRU_AVIF_LIBRARY \"${TSUMIRU_AVIF_LIBRARY}\")" COMPONENT Runtime)
  install(CODE "set(TSUMIRU_AVIF_LIB_DIR \"${TSUMIRU_AVIF_LIB_DIR}\")" COMPONENT Runtime)
  install(CODE "set(TSUMIRU_AVIF_DEST \"\$ENV{DESTDIR}${INSTALL_BUNDLE_LIB_DIR}\")" COMPONENT Runtime)
  install(CODE "set(CMAKE_OBJDUMP \"${CMAKE_OBJDUMP}\")" COMPONENT Runtime)
  install(CODE [=[
    file(GET_RUNTIME_DEPENDENCIES
      RESOLVED_DEPENDENCIES_VAR _avif_resolved
      UNRESOLVED_DEPENDENCIES_VAR _avif_unresolved
      CONFLICTING_DEPENDENCIES_PREFIX _avif_conflict
      LIBRARIES "${TSUMIRU_AVIF_LIBRARY}"
      DIRECTORIES "${TSUMIRU_AVIF_LIB_DIR}")
    if(_avif_unresolved)
      message(FATAL_ERROR "Unresolved libavif runtime dependencies: ${_avif_unresolved}")
    endif()
    if(_avif_conflict_FILENAMES)
      message(FATAL_ERROR "Conflicting libavif runtime dependencies: ${_avif_conflict_FILENAMES}")
    endif()
    set(_avif_all "${TSUMIRU_AVIF_LIBRARY}")
    list(APPEND _avif_all ${_avif_resolved})
    foreach(_dep IN LISTS _avif_all)
      get_filename_component(_name "${_dep}" NAME)
      if(NOT _dep STREQUAL TSUMIRU_AVIF_LIBRARY)
        if(_name MATCHES "^(ld-linux|libc\\.so|libm\\.so|libpthread\\.so|libdl\\.so|librt\\.so|libresolv\\.so|libgcc_s\\.so|libstdc\\+\\+\\.so)")
          continue()
        endif()
      endif()
      file(INSTALL "${_dep}" DESTINATION "${TSUMIRU_AVIF_DEST}" FOLLOW_SYMLINK_CHAIN)
    endforeach()
  ]=] COMPONENT Runtime)
endif()

# Copy native assets (Dart code-assets) into the bundle. sqlite3 3.x ships its
# own libsqlite3.so this way; without this step the .so is built but never
# bundled, so the native-asset loader can't find it, falls back to an external
# libsqlite3.so, and SQLite crashes on a null call at DB open (Linux flatpak).
install(DIRECTORY "${PROJECT_BUILD_DIR}/native_assets/linux/"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
