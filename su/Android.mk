LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE        := su
LOCAL_MODULE_TAGS   := optional
LOCAL_SRC_FILES     := su.c pts.c
LOCAL_CFLAGS        := -DANDROID -Wall -Wextra -Werror -O2
LOCAL_LDLIBS        := -lcap
LOCAL_MODULE_CLASS  := EXECUTABLES
LOCAL_MODULE_PATH   := $(TARGET_OUT_OPTIONAL_EXECUTABLES)

include $(BUILD_EXECUTABLE)
