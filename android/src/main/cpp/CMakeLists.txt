# For more information about using CMake with Android Studio, read the
# documentation: https://d.android.com/studio/projects/add-native-code.html

# 3.18 is the floor shipped with AGP 7+; a minimum below 3.5 is a hard error
# on CMake 4.x, so keep this in the 3.18..4.x compatible range.
cmake_minimum_required(VERSION 3.18)
project(flutter_midi_pro)

# FLUIDSYNTH_DIR is normally passed by build.gradle, which downloads the
# official FluidSynth Android binaries at build time (they are too large to
# ship in the package). A vendored copy at src/main/cpp/fluidsynth is used as
# a fallback for offline builds.
if(NOT DEFINED FLUIDSYNTH_DIR)
    set(FLUIDSYNTH_DIR ${CMAKE_CURRENT_SOURCE_DIR}/fluidsynth)
endif()
set(fluidsynth_DIR ${FLUIDSYNTH_DIR})
# Our code (native-lib.cpp) will be calling fluidsynth functions, so we add the fluidsynth binaries as dependencies of our code.

# The official FluidSynth Android binaries depend on libc++_shared.so but do
# not ship it; ANDROID_STL=c++_shared (set in build.gradle) makes the NDK
# provide and package it.

add_library(libFLAC SHARED IMPORTED)
set_target_properties(libFLAC PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libFLAC.so)

add_library(libfluidsynth SHARED IMPORTED)
set_target_properties(libfluidsynth PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libfluidsynth.so)

add_library(libfluidsynth-assetloader SHARED IMPORTED)
set_target_properties(libfluidsynth-assetloader PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libfluidsynth-assetloader.so)

add_library(libgio-2.0 SHARED IMPORTED)
set_target_properties(libgio-2.0 PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libgio-2.0.so)

add_library(libglib-2.0 SHARED IMPORTED)
set_target_properties(libglib-2.0 PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libglib-2.0.so)

add_library(libgmodule-2.0 SHARED IMPORTED)
set_target_properties(libgmodule-2.0 PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libgmodule-2.0.so)

add_library(libgobject-2.0 SHARED IMPORTED)
set_target_properties(libgobject-2.0 PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libgobject-2.0.so)

add_library(libgthread-2.0 SHARED IMPORTED)
set_target_properties(libgthread-2.0 PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libgthread-2.0.so)

add_library(libinstpatch-1.0 SHARED IMPORTED)
set_target_properties(libinstpatch-1.0 PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libinstpatch-1.0.so)

add_library(liboboe SHARED IMPORTED)
set_target_properties(liboboe PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/liboboe.so)

add_library(libogg SHARED IMPORTED)
set_target_properties(libogg PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libogg.so)

add_library(libopus SHARED IMPORTED)
set_target_properties(libopus PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libopus.so)

add_library(libpcre SHARED IMPORTED)
set_target_properties(libpcre PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libpcre.so)

add_library(libpcreposix SHARED IMPORTED)
set_target_properties(libpcreposix PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libpcreposix.so)

add_library(libsndfile SHARED IMPORTED)
set_target_properties(libsndfile PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libsndfile.so)

add_library(libvorbis SHARED IMPORTED)
set_target_properties(libvorbis PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libvorbis.so)

add_library(libvorbisenc SHARED IMPORTED)
set_target_properties(libvorbisenc PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libvorbisenc.so)

add_library(libvorbisfile SHARED IMPORTED)
set_target_properties(libvorbisfile PROPERTIES IMPORTED_LOCATION ${fluidsynth_DIR}/lib/${ANDROID_ABI}/libvorbisfile.so)

# Library that will be called directly from JAVA
add_library(native-lib SHARED native-lib.cpp)

# Specifies the directory where the C or C++ source coude will look the #include <yourlibrary.h> header files
target_include_directories(native-lib PRIVATE ${fluidsynth_DIR}/include)

# Link everything alltogether. Notice that native-lib should be the first element in the list.
target_link_libraries(
        native-lib
        libFLAC
        libfluidsynth
        libfluidsynth-assetloader
        libgio-2.0
        libglib-2.0
        libgmodule-2.0
        libgobject-2.0
        libgthread-2.0
        libinstpatch-1.0
        liboboe
        libogg
        libopus
        libpcre
        libpcreposix
        libsndfile
        libvorbis
        libvorbisenc
        libvorbisfile
        android
        log
)
