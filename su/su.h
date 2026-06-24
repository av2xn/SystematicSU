#ifndef SU_H
#define SU_H

#define VERSION "1.0.0"
#define VERSION_CODE 1

#define SU_PATH "/system/xbin/su"
#define DEFAULT_SHELL "/system/bin/sh"
#define DEFAULT_UID 0
#define DEFAULT_GID 0

#define SU_FLAG_SHELL    (1 << 0)
#define SU_FLAG_CMD      (1 << 1)
#define SU_FLAG_UID      (1 << 2)
#define SU_FLAG_GID      (1 << 3)
#define SU_FLAG_LOGIN    (1 << 4)
#define SU_FLAG_PRESERVE (1 << 5)

#define CAP_LAST_CAP 40

struct su_request {
    uid_t uid;
    gid_t gid;
    const char *shell;
    const char *command;
    int flags;
    int argc;
    char **argv;
};

int pts_open(char *slave_name, size_t slave_name_size);
int pts_login(const char *slave_name);

#endif
