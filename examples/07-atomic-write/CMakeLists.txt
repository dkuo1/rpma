#
# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2020, Intel Corporation
#

cmake_minimum_required(VERSION 3.3)
project(atomic-write C)

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH}
	${CMAKE_SOURCE_DIR}/../cmake
	${CMAKE_SOURCE_DIR}/../../cmake)

set(LIBPMEM_REQUIRED_VERSION 1.6)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu99")

find_package(PkgConfig QUIET)

if(PKG_CONFIG_FOUND)
	pkg_check_modules(LIBRPMA librpma)
	pkg_check_modules(LIBPMEM QUIET libpmem>=${LIBPMEM_REQUIRED_VERSION})
endif()
if(NOT LIBRPMA_FOUND)
	find_package(LIBRPMA REQUIRED librpma)
endif()
if(NOT LIBPMEM_FOUND)
	find_package(LIBPMEM ${LIBPMEM_REQUIRED_VERSION} QUIET)
endif()

link_directories(${LIBRPMA_LIBRARY_DIRS})

function(add_example name)
	set(srcs ${ARGN})
	add_executable(example-${name} ${srcs})
	target_include_directories(example-${name}
		PRIVATE
			${LIBRPMA_INCLUDE_DIRS}
			../common)
	target_link_libraries(example-${name} rpma)

	if(LIBPMEM_FOUND)
		target_include_directories(example-${name}
			PRIVATE ${LIBPMEM_INCLUDE_DIRS})
		target_link_libraries(example-${name} ${LIBPMEM_LIBRARIES})
		target_compile_definitions(example-${name}
			PRIVATE USE_LIBPMEM)
	endif()
endfunction()

add_example(server server.c ../common/common-conn.c)
add_example(client client.c ../common/common-conn.c)
