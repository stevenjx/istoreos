include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-nss-status
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=Steven

LUCI_TITLE:=NSS Hardware Offload Status & Settings
LUCI_DEPENDS:=+kmod-qca-nss-drv +kmod-qca-nss-ecm
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

$(eval $(call BuildPackage,$(PKG_NAME)))
