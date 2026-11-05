#include <stdint.h>

/* Build the Goose source as a C-host library (--header). The generated header
 * exports this fixed scalar entry; no compiler algorithm crosses this shim. */
extern void goose_init(int argc, char **argv);
extern int32_t blot_goose_main(void);
extern void blot_platform_entry_init(int argc, char **argv);

int main(int argc, char **argv) {
    blot_platform_entry_init(argc, argv);
    goose_init(argc, argv);
    return blot_goose_main();
}
