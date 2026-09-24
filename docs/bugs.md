# Bug log

Anything that took more than ~30 min: symptom, how I found it, fix.

## M0 – Verilator can't find the testbench
- **Symptom:** `No rule to make target 'tb/tb_counter.cpp'`
- **Cause:** with `--Mdir build/obj_x`, Verilator's generated makefile runs from inside that folder, so relative `.cpp` paths break.
- **Fix:** pass the testbench path through `$(abspath ...)` in the Makefile.

## M0 – Space in folder path breaks make
- **Symptom:** `Cannot find file containing module: '/Users/Abhi/Documents/RISC-V'`
- **Cause:** project lived in "RISC-V project"; make splits paths on spaces.
- **Fix:** renamed the folder to `RISC-V-project`. Rule: no spaces anywhere in the path.

## M0 – `lz4.h` not found on macOS
- **Symptom:** `fstcpp_writer.cpp: fatal error: 'lz4.h' file not found` (Verilator 5.052, Homebrew)
- **Cause:** Verilator's FST trace writer uses lz4, but the Homebrew bottle doesn't pull it in, and Apple clang doesn't search /opt/homebrew/include.
- **Fix:** `brew install lz4`, and the Makefile passes `-I$(brew --prefix)/include` and `-L.../lib -llz4` to Verilator's C++ build.

## M0 – "permission denied: Makefile"
- **Symptom:** appending to the Makefile failed with `zsh: permission denied`.
- **Cause:** a few files came out of the zip read-only.
- **Fix:** `chmod -R u+w .` in the project folder.
