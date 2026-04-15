cmake_minimum_required(VERSION 3.20)
project(pokitd CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Bluetooth Network)

# libQtPokit ships from our dokit derivation ($out/lib + $out/include/qtpokit).
# No CMake config module upstream, so locate manually.
find_library(QTPOKIT_LIBRARY NAMES QtPokit REQUIRED)
find_path(QTPOKIT_INCLUDE_DIR NAMES qtpokit/pokitdevice.h REQUIRED)

add_executable(pokitd
    main.cpp
    server.cpp
    session.cpp
    device.cpp
    json.cpp
)

target_include_directories(pokitd PRIVATE ${QTPOKIT_INCLUDE_DIR})

target_link_libraries(pokitd PRIVATE
    ${QTPOKIT_LIBRARY}
    Qt6::Core
    Qt6::Bluetooth
    Qt6::Network
)

install(TARGETS pokitd RUNTIME DESTINATION bin)
