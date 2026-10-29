// SPDX-License-Identifier: 0BSD

///////////////////////////////////////////////////////////////////////////////
//
/// \file       tuktest.h
/// \brief      Helper macros for writing simple test programs
/// \version    2024-02-14
///
/// Some inspiration was taken from Seatest by Keith Nicholas and
/// from STest which is a fork of Seatest by Jia Tan.
///
/// This is standard C99/C11 only and thus should be fairly portable
/// outside POSIX systems too.
///
/// This supports putting multiple tests in a single test program
/// although it is perfectly fine to have only one test per program.
/// Each test can produce one of these results:
///   - Pass
///   - Fail
///   - Skip
///   - Hard error (the remaining tests, if any, are not run)
///
/// By default this produces an exit status that is compatible with
/// Automake and Meson, and mostly compatible with CMake.[1]
/// If a test program contains multiple tests, only one exit code can
/// be returned. Of the following, the first match is used:
///   - 99 if any test returned a hard error
///   - stdlib.h's EXIT_FAILURE if at least one test failed
///   - 77 if at least one test was skipped or no tests were run at all
///   - stdlib.h's EXIT_SUCCESS (0 on POSIX); that is, if none of the above
///     are true then there was at least one test to run and none of them
///     failed, was skipped, or returned a hard error.
///
/// A summary of tests being run and their results are printed to stdout.
/// If you want ANSI coloring for the output, #define TUKTEST_COLOR.
/// If you only want output when something goes wrong, #define TUKTEST_QUIET.
///
/// The downside of the above mapping is that it cannot indicate if
/// some tests were skipped and some passed. If that is likely to
/// happen it may be better to split into multiple test programs (one
/// test per program) or use the TAP mode described below.
///
/// By using #define TUKTEST_TAP before #including this file the
/// output will be Test Anything Protocol (TAP) version 12 compatible
/// and the exit status will always be EXIT_SUCCESS. This can be easily
/// used with Automake via its tap-driver.sh. Meson supports TAP natively.
/// TAP's todo-directive isn't supported for now, mostly because it's not
/// trivially convertible to the exit-status reporting method.
///
/// If TUKTEST_TAP is used, TUKTEST_QUIET and TUKTEST_COLOR are ignored.
///
/// The main() function may look like this (remember to include config.h
/// or such files too if needed!):
///
///     #include "tuktest.h"
///
///     int main(int argc, char **argv)
///     {
///         tuktest_start(argc, argv);
///
///         if (!is_package_foo_available())
///             tuktest_early_skip("Optional package foo is not available");
///
///         if (!do_common_initializations())
///             tuktest_error("Error during common initializations");
///
///         tuktest_run(testfunc1);
///         tuktest_run(testfunc2);
///
///         return tuktest_end();
///     }
///
//