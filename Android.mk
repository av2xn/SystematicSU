LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE        := systematicsu
LOCAL_MODULE_TAGS   := optional
LOCAL_REQUIRED_MODULES := su
include $(BUILD_PHONY_PACKAGE)

include $(LOCAL_PATH)/su/Android.mk
