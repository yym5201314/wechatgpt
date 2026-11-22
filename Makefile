# Manual bubble-menu AI reply and on-demand chat analysis. No message send hooks.
TARGET := iphone:clang:latest:14.0
ARCHS := arm64
THEOS_PACKAGE_SCHEME ?= rootless
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = zhushou
zhushou_FILES = Tweak.xm src/DGPTConfig.m src/DGPTClient.m src/DGPTUI.m src/DGPTMessageReply.m src/DGPTNativeMenu.m src/DGPTWeChatBridge.m src/DGPTAnalysisVC.m
zhushou_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
zhushou_FRAMEWORKS = UIKit Foundation Security QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
