#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/prctl.h>
#include <sys/capability.h>
#include <pwd.h>
#include <grp.h>

#include "su.h"
#include "pts.h"

static void usage(const char *progname) {
    fprintf(stderr,
        "SystematicSU %s\n"
        "Usage: %s [OPTIONS] [--] [COMMAND [ARGS...]]\n"
        "\n"
        "  -u, --uid <uid>     target uid (default: 0)\n"
        "  -g, --gid <gid>     target gid (default: 0)\n"
        "  -s, --shell <path>  shell to execute (default: " DEFAULT_SHELL ")\n"
        "  -c, --command <cmd> command to execute in shell\n"
        "  -l, --login         simulate login shell\n"
        "  -p, --preserve-env  preserve environment\n"
        "  -v, --version       print version\n"
        "  -h, --help          print this help\n",
        VERSION, progname);
}

static void set_identity(uid_t uid, gid_t gid) {
    if (prctl(PR_SET_KEEPCAPS, 1, 0, 0, 0) < 0) {
        perror("prctl PR_SET_KEEPCAPS");
        exit(EXIT_FAILURE);
    }

    if (setgroups(0, NULL) < 0) {
        perror("setgroups");
        exit(EXIT_FAILURE);
    }

    if (setresgid(gid, gid, gid) < 0) {
        perror("setresgid");
        exit(EXIT_FAILURE);
    }

    if (setresuid(uid, uid, uid) < 0) {
        perror("setresuid");
        exit(EXIT_FAILURE);
    }
}

static void set_capabilities(void) {
    struct __user_cap_header_struct header = {
        .version = _LINUX_CAPABILITY_VERSION_3,
        .pid = 0
    };

    struct __user_cap_data_struct data[2];
    memset(data, 0, sizeof(data));

    data[0].effective   = 0xFFFFFFFF;
    data[0].permitted   = 0xFFFFFFFF;
    data[0].inheritable = 0xFFFFFFFF;
    data[1].effective   = 0xFFFFFFFF;
    data[1].permitted   = 0xFFFFFFFF;
    data[1].inheritable = 0xFFFFFFFF;

    if (capset(&header, data) < 0) {
        perror("capset");
        exit(EXIT_FAILURE);
    }
}

static char **build_envp(const struct su_request *req, char *const *old_envp) {
    if (req->flags & SU_FLAG_PRESERVE)
        return (char **)old_envp;

    static char *envp[32];
    int i = 0;

    struct passwd *pw = getpwuid(req->uid);
    if (pw) {
        static char home_buf[256];
        static char user_buf[64];
        static char shell_buf[256];
        static char logname_buf[64];

        snprintf(home_buf,    sizeof(home_buf),    "HOME=%s",    pw->pw_dir);
        snprintf(user_buf,    sizeof(user_buf),    "USER=%s",    pw->pw_name);
        snprintf(shell_buf,   sizeof(shell_buf),   "SHELL=%s",   req->shell);
        snprintf(logname_buf, sizeof(logname_buf), "LOGNAME=%s", pw->pw_name);

        envp[i++] = home_buf;
        envp[i++] = user_buf;
        envp[i++] = shell_buf;
        envp[i++] = logname_buf;
    }

    envp[i++] = "PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin";
    envp[i]   = NULL;

    return envp;
}

static void exec_shell(const struct su_request *req, char *const *envp) {
    if (req->command) {
        char *args[] = {
            (char *)req->shell,
            "-c",
            (char *)req->command,
            NULL
        };
        execve(req->shell, args, envp);
        perror("execve");
        exit(EXIT_FAILURE);
    }

    if (req->argc > 0) {
        execve(req->argv[0], req->argv, envp);
        perror("execve");
        exit(EXIT_FAILURE);
    }

    const char *shell_name = strrchr(req->shell, '/');
    shell_name = shell_name ? shell_name + 1 : req->shell;

    char login_name[128];
    if (req->flags & SU_FLAG_LOGIN)
        snprintf(login_name, sizeof(login_name), "-%s", shell_name);
    else
        strncpy(login_name, shell_name, sizeof(login_name) - 1);

    char *args[] = { login_name, NULL };
    execve(req->shell, args, envp);
    perror("execve");
    exit(EXIT_FAILURE);
}

int main(int argc, char *argv[], char *envp[]) {
    struct su_request req = {
        .uid   = DEFAULT_UID,
        .gid   = DEFAULT_GID,
        .shell = DEFAULT_SHELL,
        .flags = 0,
    };

    static struct option long_opts[] = {
        { "uid",          required_argument, NULL, 'u' },
        { "gid",          required_argument, NULL, 'g' },
        { "shell",        required_argument, NULL, 's' },
        { "command",      required_argument, NULL, 'c' },
        { "login",        no_argument,       NULL, 'l' },
        { "preserve-env", no_argument,       NULL, 'p' },
        { "version",      no_argument,       NULL, 'v' },
        { "help",         no_argument,       NULL, 'h' },
        { NULL, 0, NULL, 0 }
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "u:g:s:c:lpvh", long_opts, NULL)) != -1) {
        switch (opt) {
        case 'u':
            req.uid = (uid_t)atoi(optarg);
            req.flags |= SU_FLAG_UID;
            break;
        case 'g':
            req.gid = (gid_t)atoi(optarg);
            req.flags |= SU_FLAG_GID;
            break;
        case 's':
            req.shell = optarg;
            req.flags |= SU_FLAG_SHELL;
            break;
        case 'c':
            req.command = optarg;
            req.flags |= SU_FLAG_CMD;
            break;
        case 'l':
            req.flags |= SU_FLAG_LOGIN;
            break;
        case 'p':
            req.flags |= SU_FLAG_PRESERVE;
            break;
        case 'v':
            printf("SystematicSU %s\n", VERSION);
            return EXIT_SUCCESS;
        case 'h':
            usage(argv[0]);
            return EXIT_SUCCESS;
        default:
            usage(argv[0]);
            return EXIT_FAILURE;
        }
    }

    if (optind < argc) {
        req.argv = &argv[optind];
        req.argc = argc - optind;
    }

    set_identity(req.uid, req.gid);
    set_capabilities();

    char **new_envp = build_envp(&req, envp);

    exec_shell(&req, new_envp);

    return EXIT_FAILURE;
}
