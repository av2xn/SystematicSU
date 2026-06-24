#ifndef PTS_H
#define PTS_H

#include <stddef.h>

int pts_open(char *slave_name, size_t slave_name_size);
int pts_login(const char *slave_name);

#endif
