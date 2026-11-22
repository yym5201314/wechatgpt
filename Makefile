DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

include AxsWeChatGPTBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AxsWeChatGPT
AxsWeChatGPT_FILES = $(wildcard Hooks/*.xm Sources/*.m Controllers/*.m)
AxsWeChatGPT_CFLAGS = -fobjc-arc -I./Headers -I./Sources -I./Controllers
AxsWeChatGPT_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsWeChatGPT_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
