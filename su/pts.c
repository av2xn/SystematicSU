#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <sys/types.h>

#include "pts.h"

int pts_open(char *slave_name, size_t slave_name_size) {
    int master_fd = posix_openpt(O_RDWR | O_NOCTTY);
    if (master_fd < 0)
        return -1;

    if (grantpt(master_fd) < 0) {
        close(master_fd);
        return -1;
    }

    if (unlockpt(master_fd) < 0) {
        close(master_fd);
        return -1;
    }

    char *name = ptsname(master_fd);
    if (!name) {
        close(master_fd);
        return -1;
    }

    if (slave_name && slave_name_size > 0)
        strncpy(slave_name, name, slave_name_size - 1);

    return master_fd;
}

int pts_login(const char *slave_name) {
    int slave_fd = open(slave_name, O_RDWR | O_NOCTTY);
    if (slave_fd < 0)
        return -1;

    if (setsid() < 0) {
        close(slave_fd);
        return -1;
    }

    if (ioctl(slave_fd, TIOCSCTTY, 1) < 0) {
        close(slave_fd);
        return -1;
    }

    dup2(slave_fd, STDIN_FILENO);
    dup2(slave_fd, STDOUT_FILENO);
    dup2(slave_fd, STDERR_FILENO);

    if (slave_fd > STDERR_FILENO)
        close(slave_fd);

    return 0;
}
