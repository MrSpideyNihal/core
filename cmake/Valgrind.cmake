#
# Valgrind module for MetaCall
#

option(OPTION_BUILD_PROFILING "Builds targets with profiling applied" OFF)

find_program(VALGRIND_EXECUTABLE valgrind)

if (NOT VALGRIND_EXECUTABLE AND OPTION_BUILD_PROFILING)
  message(WARNING "Unable to create Valgrind targets due to missing program")
endif()

macro(_metacall_valgrind_basic_setup _target)
  if (NOT TARGET ${_target})
    message(FATAL_ERROR "Specified target \"${_target}\" does not exist")
  endif()

  get_target_property(_target_type ${_target} TYPE)
  if (NOT _target_type STREQUAL EXECUTABLE)
    message(FATAL_ERROR "Specified target \"${_target}\" must be an executable type to register for profiling with Valgrind")
  endif()

  if (NOT (${CMAKE_BUILD_TYPE} STREQUAL "Debug" OR
           ${CMAKE_BUILD_TYPE} STREQUAL "RelWithDebInfo"))
    message(STATUS "Use Debug or RelWithDebInfo as cmake build type to get debug info from Valgrind")
  endif()

  if (NOT (VALGRIND_EXECUTABLE AND OPTION_BUILD_PROFILING) OR CMAKE_CROSSCOMPILING)
    return()
  endif()

  if (NOT TARGET valgrind-all)
    add_custom_target(valgrind-all)
  endif()
endmacro()

macro(_metacall_valgrind_arguments_setup _target _tool_name _toolOptions _toolSingle _toolMulti _ARGN)
  set(_commonOptions CHILD_SILENT_AFTER_FORK TRACE_CHILDREN)
  set(_commonSingle NAME WORKING_DIRECTORY REPORT_DIRECTORY)
  set(_commonMulti PROGRAM_ARGS)

  set(_argOption ${_commonOptions} ${_toolOptions})
  set(_argSingle ${_commonSingle} ${_toolSingle})
  set(_argMulti ${_commonMulti} ${_toolMulti})

  cmake_parse_arguments(x "${_argOption}" "${_argSingle}" "${_argMulti}" ${_ARGN})

  if(x_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "Unparsed arguments ${x_UNPARSED_ARGUMENTS}")
  endif()

  set(target_name valgrind-${_tool_name}-${_target})
  set(report_folder ${_tool_name}-${_target})
  if (x_NAME)
    set(target_name valgrind-${_tool_name}-${x_NAME})
    set(report_folder ${_tool_name}-${x_NAME})
  endif()

  set(working_directory ${CMAKE_CURRENT_BINARY_DIR})
  if (x_WORKING_DIRECTORY)
    set(working_directory ${x_WORKING_DIRECTORY})
  endif()

  set(report_directory ${CMAKE_BINARY_DIR}/profiling/valgrind-reports)
  if (x_REPORT_DIRECTORY)
    set(report_directory ${x_REPORT_DIRECTORY})
  endif()

  set(output_file ${report_directory}/${report_folder}/${target_name})

  unset(valgrind_tool_options)
  if (x_CHILD_SILENT_AFTER_FORK)
    list(APPEND valgrind_tool_options --child-silent-after-fork=yes)
  endif()

  if (x_TRACE_CHILDREN)
    list(APPEND valgrind_tool_options --trace-children=yes)
    list(APPEND valgrind_tool_options --log-file=${output_file}.log.%p)
  else()
    list(APPEND valgrind_tool_options --log-file=${output_file}.log)
  endif()
endmacro()

macro(_metacall_setup_custom_target valgrind_tool target_name target)
  add_custom_target(${target_name}
    COMMENT "Valgrind ${valgrind_tool} is running for \"${target}\" (output: \"${report_directory}/${report_folder}\")"
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${report_directory}/${report_folder}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${report_directory}/${report_folder}
    COMMAND ${VALGRIND_EXECUTABLE} ${valgrind_tool_options} $<TARGET_FILE:${target}> ${x_PROGRAM_ARGS}
    WORKING_DIRECTORY ${working_directory}
    DEPENDS ${target}
  )
  if (NOT TARGET valgrind-${valgrind_tool})
    add_custom_target(valgrind-${valgrind_tool})
  endif()
  add_dependencies(valgrind-${valgrind_tool} ${target_name})
  add_dependencies(valgrind-all valgrind-${valgrind_tool})
endmacro()

function(metacall_add_valgrind_memcheck target)
  set(argOption SHOW_REACHABLE TRACK_ORIGINS UNDEF_VALUE_ERRORS)
  set(argSingle LEAK_CHECK SUPPRESSIONS_FILE)
  set(argMulti "")

  set(valgrind_tool memcheck)
  _metacall_valgrind_basic_setup(${target})
  _metacall_valgrind_arguments_setup(${target} ${valgrind_tool} "${argOption}" "${argSingle}" "${argMulti}" "${ARGN}")

  if (NOT VALGRIND_EXECUTABLE OR NOT OPTION_BUILD_PROFILING)
    return()
  endif()

  list(APPEND valgrind_tool_options --tool=${valgrind_tool})
  list(APPEND valgrind_tool_options --track-origins=yes)

  if (x_SHOW_REACHABLE)
    list(APPEND valgrind_tool_options --show-reachable=yes)
  endif()

  if (x_UNDEF_VALUE_ERRORS)
    list(APPEND valgrind_tool_options --undef-value-errors=yes)
  endif()

  if (x_LEAK_CHECK)
    list(APPEND valgrind_tool_options "--leak-check=${x_LEAK_CHECK}")
  else()
    list(APPEND valgrind_tool_options "--leak-check=full")
  endif()

  if (x_SUPPRESSIONS_FILE)
    list(APPEND valgrind_tool_options "--suppressions=${CMAKE_SOURCE_DIR}/${x_SUPPRESSIONS_FILE}")
  endif()

  _metacall_setup_custom_target(${valgrind_tool} ${target_name} ${target})
endfunction()

function(metacall_add_valgrind_helgrind target)
  set(argOption "")
  set(argSingle SUPPRESSIONS_FILE)
  set(argMulti "")

  set(valgrind_tool helgrind)
  _metacall_valgrind_basic_setup(${target})
  _metacall_valgrind_arguments_setup(${target} ${valgrind_tool} "${argOption}" "${argSingle}" "${argMulti}" "${ARGN}")

  if (NOT VALGRIND_EXECUTABLE OR NOT OPTION_BUILD_PROFILING)
    return()
  endif()

  list(APPEND valgrind_tool_options --tool=${valgrind_tool})
  list(APPEND valgrind_tool_options --history-level=approx)

  # For JITs
  list(APPEND valgrind_tool_options --smc-check=all-non-file)

  if (x_SUPPRESSIONS_FILE)
    list(APPEND valgrind_tool_options "--suppressions=${CMAKE_SOURCE_DIR}/${x_SUPPRESSIONS_FILE}")
  endif()

  _metacall_setup_custom_target(${valgrind_tool} ${target_name} ${target})
endfunction()
