include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-tanwrt-tempStatus
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=TanWRT <tancan@example.com>

LUCI_TITLE:=TanWRT Temperature Status
LUCI_DEPENDS:=+luci-base +rpcd +ucode-mod-uci
LUCI_PKGARCH:=all
LUCI_DESCRIPTION:=Realtime CPU/motherboard temperature monitoring with trend chart and threshold alarms for LuCI2.

define Package/luci-app-tanwrt-tempStatus/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
rm -f /tmp/luci-indexcache* 2>/dev/null || true
rm -rf /tmp/luci-modulecache/* 2>/dev/null || true
for d in /www/luci-static/resources/tanwrt /www/luci-static/resources/view/tanwrt /www/luci-static/resources/view/status/include; do
	if [ -d "$$d" ]; then
		find "$$d" -type f -name '*.js' -exec touch {} + 2>/dev/null || true
	fi
done
if [ -x /etc/init.d/rpcd ]; then
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
fi
exit 0
endef

define Package/luci-app-tanwrt-tempStatus/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
rm -f /tmp/luci-indexcache* 2>/dev/null || true
rm -rf /tmp/luci-modulecache/* 2>/dev/null || true
if [ -x /etc/init.d/rpcd ]; then
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
fi
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
