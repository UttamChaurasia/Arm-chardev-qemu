# Sourced by gdb-demo.sh and trace-oops.sh.
#
# A module's DWARF debug info records the absolute source path it was compiled
# from. If the tree is later moved or unzipped elsewhere, GDB cannot find the
# source unless told to map the old path to the new one. Read the old path out
# of the .ko itself (grep -a: no binutils needed) instead of hard-coding it.

# built_at <module.ko>  -> directory the module was built in (empty if unknown)
built_at() {
    grep -a -o '/[A-Za-z0-9_./-]*/src/[A-Za-z0-9_]*\.c' "$1" 2>/dev/null \
        | head -1 | sed 's|/src/[^/]*$||'
}
