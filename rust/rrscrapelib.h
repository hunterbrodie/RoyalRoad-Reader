#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

char *enforce_binding(void);

char *const *search(const char *title);

void init_scrape(const char *url, const char *dir_str);

void update(const char *dir);
