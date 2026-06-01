ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LqFPSOptimizer
LqFPSOptimizer_FILES = Tweak.xm
LqFPSOptimizer_FRAMEWORKS = UIKit Security

include $(THEOS)/makefiles/tweak.mk
