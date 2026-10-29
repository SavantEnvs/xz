// Leak detection off at build time (ASan stays on): this fleet fuzzes for memory corruption/UB, not leaks.
extern "C" int __lsan_is_turned_off() { return 1; }
