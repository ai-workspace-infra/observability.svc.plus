import copy
import json


CONTROL_PLANE_PATH = "files/grafana/11-paas-control-plane/pigsty.json"
OUTPUT_PATH = "files/grafana/homepage.json"

VISIBLE_VARS = [
    {
        "name": "version",
        "type": "constant",
        "query": "v4.0.0",
        "hide": 2,
    },
    {
        "name": "origin_prometheus",
        "label": "数据源",
        "type": "query",
        "datasource": {"uid": "ds-prometheus"},
        "query": "label_values(kube_node_info,origin_prometheus)",
        "refresh": 1,
    },
    {
        "name": "interval",
        "label": "采样间隔",
        "type": "interval",
        "query": "3m,5m,10m,30m,1h,6h,12h,1d",
    },
]

DOMAIN_SECTIONS = [
    {
        "title": "IAAS资源",
        "items": [
            {
                "title": "计算",
                "description": "主机容量、节点健康、实例告警",
                "folder_uid": "01-iaas-compute",
                "folder_title": "IAAS / 计算",
                "tag": "IAAS-COMPUTE",
                "highlights": ["Node Overview", "Node Instance", "Node Alert"],
                "dash_height": 9,
            },
            {
                "title": "存储",
                "description": "磁盘、卷、对象存储、JuiceFS",
                "folder_uid": "02-iaas-storage",
                "folder_title": "IAAS / 存储",
                "tag": "IAAS-STORAGE",
                "highlights": ["Node Disk", "MinIO Overview", "Node JuiceFS"],
                "dash_height": 9,
            },
            {
                "title": "网络",
                "description": "VIP、节点网络、底层连通性",
                "folder_uid": "03-iaas-network",
                "folder_title": "IAAS / 网络",
                "tag": "IAAS-NETWORK",
                "highlights": ["Node VIP"],
                "dash_height": 8,
            },
        ],
    },
    {
        "title": "PaaS服务",
        "items": [
            {
                "title": "平台控制面",
                "description": "Grafana、Victoria、Alertmanager、Etcd、CMDB",
                "folder_uid": "11-paas-control-plane",
                "folder_title": "PaaS / 平台控制面",
                "tag": "PAAS-CONTROL-PLANE",
                "highlights": ["Infra Overview", "Victoria Metrics", "Alert Manager"],
                "dash_height": 10,
            },
            {
                "title": "集群",
                "description": "K8S 集群资源、命名空间与工作负载入口",
                "folder_uid": "12-paas-cluster",
                "folder_title": "PaaS / 集群",
                "tag": "PAAS-CLUSTER",
                "highlights": ["K8S Dashboard"],
                "dash_height": 8,
            },
            {
                "title": "DB",
                "description": "PGSQL、PGRDS、PGCAT、Ferret",
                "folder_uid": "13-paas-db",
                "folder_title": "PaaS / DB",
                "tag": "PAAS-DB",
                "highlights": ["PGSQL Overview", "PGSQL Cluster", "PGCAT Instance"],
                "dash_height": 14,
            },
            {
                "title": "缓存",
                "description": "Redis 集群、实例与缓存服务运行面",
                "folder_uid": "14-paas-cache",
                "folder_title": "PaaS / 缓存",
                "tag": "PAAS-CACHE",
                "highlights": ["Redis Overview", "Redis Cluster"],
                "dash_height": 9,
            },
        ],
    },
    {
        "title": "业务单元",
        "items": [
            {
                "title": "代理",
                "description": "Nginx、HAProxy 与流量接入层",
                "folder_uid": "22-bu-proxy",
                "folder_title": "业务单元 / 代理",
                "tag": "BU-PROXY",
                "highlights": ["Nginx Instance", "Node HAProxy"],
                "dash_height": 8,
            },
            {
                "title": "请求",
                "description": "请求日志、会话、链路与请求级观测",
                "folder_uid": "24-bu-request",
                "folder_title": "业务单元 / 请求",
                "tag": "BU-REQUEST",
                "highlights": ["PGLOG Overview", "Logs Instance", "Node Vector"],
                "dash_height": 9,
            },
        ],
    },
]


def shift_panel(panel, delta_y):
    panel["gridPos"]["y"] += delta_y
    for nested in panel.get("panels", []):
        shift_panel(nested, delta_y)


def clone_panel(panel, x, y, w=None, h=None):
    cloned = copy.deepcopy(panel)
    cloned["gridPos"] = {
        "x": x,
        "y": y,
        "w": w if w is not None else panel["gridPos"]["w"],
        "h": h if h is not None else panel["gridPos"]["h"],
    }
    return cloned


def make_text_panel(panel_id, title, html, x, y, w, h, transparent=True):
    return {
        "id": panel_id,
        "type": "text",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "transparent": transparent,
        "options": {"content": html, "mode": "html"},
    }


def make_row_panel(panel_id, title, y):
    return {
        "id": panel_id,
        "type": "row",
        "title": title,
        "collapsed": False,
        "panels": [],
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": y},
    }


def make_dashlist_panel(panel_id, title, tags, x, y, w, h, max_items=12):
    return {
        "id": panel_id,
        "type": "dashlist",
        "title": title,
        "pluginVersion": "12.3.0",
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "options": {
            "includeVars": True,
            "keepTime": True,
            "maxItems": max_items,
            "query": "",
            "showFolderNames": False,
            "showHeadings": False,
            "showRecentlyViewed": False,
            "showSearch": False,
            "showStarred": False,
            "tags": tags,
        },
    }


def summary_card_html(item):
    highlights = "".join(
        f"<li style='margin:0 0 4px 18px;'>{highlight}</li>"
        for highlight in item["highlights"]
    )
    return f"""
<div style="border:1px solid #d1d5db;border-radius:16px;padding:14px 16px;background:#fbfdff;height:100%;">
  <div style="font-size:12px;color:#6b7280;margin-bottom:6px;">{item['folder_title']}</div>
  <div style="font-size:20px;font-weight:800;color:#111827;margin-bottom:8px;">{item['title']}</div>
  <div style="font-size:13px;line-height:1.5;color:#4b5563;">{item['description']}</div>
  <ul style="margin:10px 0 12px 0;padding:0;color:#111827;font-size:13px;line-height:1.45;">{highlights}</ul>
  <div style="display:inline-block;padding:8px 12px;border-radius:999px;background:#e5e7eb;color:#374151;font-size:12px;font-weight:700;">
    右侧保留可跳转目录
  </div>
</div>
"""


def homepage_nav_html():
    return """
<div style="display:flex;justify-content:space-between;align-items:center;gap:16px;flex-wrap:wrap;padding:8px 4px 2px 4px;">
  <div>
    <div style="font-size:12px;color:#6b7280;margin-bottom:6px;">Platform Engineering Home</div>
    <div style="font-size:28px;font-weight:800;color:#111827;">平台工程总览入口</div>
    <div style="font-size:13px;color:#4b5563;margin-top:6px;">首页只保留全局脉搏、资源域摘要与跳转，详细明细统一下沉到二级 dashboard。</div>
  </div>
  <div style="display:flex;gap:12px;flex-wrap:wrap;">
    <span style="padding:10px 16px;border-radius:999px;background:#dbeafe;color:#1d4ed8;font-weight:700;">IAAS资源</span>
    <span style="padding:10px 16px;border-radius:999px;background:#ecfdf3;color:#047857;font-weight:700;">PaaS服务</span>
    <span style="padding:10px 16px;border-radius:999px;background:#fff7ed;color:#c2410c;font-weight:700;">业务单元</span>
  </div>
</div>
"""


def homepage_guide_html():
    return """
<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;padding:4px 2px 0 2px;">
  <div style="border:1px solid #d1d5db;border-radius:12px;padding:12px 14px;background:#fbfdff;">
    <div style="font-size:12px;color:#6b7280;margin-bottom:6px;">IAAS资源</div>
    <div style="font-size:14px;font-weight:700;color:#111827;">计算 / 存储 / 网络</div>
    <div style="font-size:12px;color:#6b7280;margin-top:6px;">先看宿主、磁盘、VIP 与底层资源是否健康。</div>
  </div>
  <div style="border:1px solid #d1d5db;border-radius:12px;padding:12px 14px;background:#fbfdff;">
    <div style="font-size:12px;color:#6b7280;margin-bottom:6px;">PaaS服务</div>
    <div style="font-size:14px;font-weight:700;color:#111827;">控制面 / 集群 / DB / 缓存</div>
    <div style="font-size:12px;color:#6b7280;margin-top:6px;">平台自身与共享服务按资源域稳定分层。</div>
  </div>
  <div style="border:1px solid #d1d5db;border-radius:12px;padding:12px 14px;background:#fbfdff;">
    <div style="font-size:12px;color:#6b7280;margin-bottom:6px;">业务单元</div>
    <div style="font-size:14px;font-weight:700;color:#111827;">代理 / 请求</div>
    <div style="font-size:12px;color:#6b7280;margin-top:6px;">业务接入面与请求观测单独收口，不再混在底层资源里。</div>
  </div>
</div>
"""


def select_platform_summary_panels(control_plane):
    wanted = ["Pigsty ${version}", "Modules", "Instances", "Firing Alerts"]
    by_title = {panel.get("title"): panel for panel in control_plane.get("panels", [])}
    return [by_title[title] for title in wanted if title in by_title]


def add_domain_section(homepage, start_id, current_y, section):
    panel_id = start_id
    homepage["panels"].append(make_row_panel(panel_id, section["title"], current_y))
    panel_id += 1
    current_y += 1

    width = 24 // len(section["items"])
    summary_height = 5
    max_dash_height = max(item["dash_height"] for item in section["items"])

    for index, item in enumerate(section["items"]):
        x = width * index
        homepage["panels"].append(
            make_text_panel(
                panel_id,
                f"{item['title']}摘要",
                summary_card_html(item),
                x,
                current_y,
                width,
                summary_height,
            )
        )
        panel_id += 1

    current_y += summary_height

    for index, item in enumerate(section["items"]):
        x = width * index
        homepage["panels"].append(
            make_dashlist_panel(
                panel_id,
                f"{item['title']}目录",
                [item["tag"]],
                x,
                current_y,
                width,
                item["dash_height"],
                max_items=20,
            )
        )
        panel_id += 1

    current_y += max_dash_height
    return panel_id, current_y


def merge_dashboards():
    with open(CONTROL_PLANE_PATH, "r") as handle:
        control_plane = json.load(handle)

    homepage = {
        "annotations": control_plane.get("annotations", {"list": []}),
        "description": "Platform engineering entry dashboard",
        "editable": True,
        "graphTooltip": 0,
        "id": None,
        "links": control_plane.get("links", []),
        "panels": [],
        "schemaVersion": 39,
        "tags": ["HOME", "Platform"],
        "templating": {"list": VISIBLE_VARS},
        "time": control_plane.get("time", {"from": "now-1h", "to": "now"}),
        "timepicker": control_plane.get("timepicker", {}),
        "timezone": "browser",
        "title": "Homepage",
        "uid": "home",
        "version": 1,
    }

    panel_id = 1
    homepage["panels"].append(
        make_text_panel(panel_id, "总览导航", homepage_nav_html(), 0, 0, 24, 3)
    )
    panel_id += 1
    homepage["panels"].append(
        make_text_panel(panel_id, "结构说明", homepage_guide_html(), 0, 3, 24, 5)
    )
    panel_id += 1

    current_y = 8
    homepage["panels"].append(make_row_panel(panel_id, "平台脉搏", current_y))
    panel_id += 1
    current_y += 1

    summary_layout = [
        ("Pigsty ${version}", 0, 4, 4, 7),
        ("Modules", 4, 4, 4, 7),
        ("Instances", 8, 4, 8, 7),
        ("Firing Alerts", 16, 4, 8, 7),
    ]
    summary_panels = {panel.get("title"): panel for panel in select_platform_summary_panels(control_plane)}
    for title, x, y, w, h in summary_layout:
        if title not in summary_panels:
            continue
        homepage["panels"].append(clone_panel(summary_panels[title], x, y, w, h))
        panel_id += 1
    current_y += 7

    for section in DOMAIN_SECTIONS:
        panel_id, current_y = add_domain_section(homepage, panel_id, current_y, section)

    for index, panel in enumerate(homepage["panels"], 1):
        panel["id"] = index

    with open(OUTPUT_PATH, "w") as handle:
        json.dump(homepage, handle, indent=2)


if __name__ == "__main__":
    merge_dashboards()
