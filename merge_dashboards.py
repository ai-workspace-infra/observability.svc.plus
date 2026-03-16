import json
import re
import os


def shift_panel(panel, delta_y):
    panel["gridPos"]["y"] += delta_y
    for nested in panel.get("panels", []):
        shift_panel(nested, delta_y)


def make_text_panel(panel_id, title, html, x, y, w, h, transparent=True):
    return {
        "id": panel_id,
        "type": "text",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "transparent": transparent,
        "options": {
            "content": html,
            "mode": "html"
        }
    }


def merge_dashboards():
    # Paths to source dashboards
    pig_path = 'files/grafana/pigsty.json'
    node_path = 'files/grafana/node.json'
    k8s_path = 'files/grafana/k8s.json'
    output_path = 'files/grafana/homepage.json'

    # Read raw contents
    with open(pig_path, 'r') as f:
        pig_raw = f.read()
    with open(node_path, 'r') as f:
        node_raw = f.read()
    with open(k8s_path, 'r') as f:
        k8s_raw = f.read()

    # Perform fixed variable mapping for node.json
    # $name -> $hostname, $instance -> $node, $show_name -> $show_hostname
    node_raw = re.sub(r'\$name\b', '$hostname', node_raw)
    node_raw = re.sub(r'\$\{name\}', '${hostname}', node_raw)
    node_raw = re.sub(r'\$instance\b', '$node', node_raw)
    node_raw = re.sub(r'\$\{instance\}', '${node}', node_raw)
    node_raw = re.sub(r'\$show_name\b', '$show_hostname', node_raw)
    node_raw = re.sub(r'\$\{show_name\}', '${show_hostname}', node_raw)

    pig = json.loads(pig_raw)
    node = json.loads(node_raw)
    k8s = json.loads(k8s_raw)

    # Base dashboard
    homepage = {
        "annotations": pig.get("annotations", {"list": []}),
        "description": "Pigsty Consolidated Homepage",
        "editable": True,
        "graphTooltip": 0,
        "id": None,
        "links": pig.get("links", []),
        "panels": [],
        "schemaVersion": 39,
        "tags": ["HOME", "Pigsty"],
        "templating": {"list": []},
        "time": pig.get("time", {"from": "now-1h", "to": "now"}),
        "timepicker": pig.get("timepicker", {}),
        "timezone": "browser",
        "title": "Homepage",
        "uid": "home",
        "version": 1
    }

    # Unified Variables
    unified_vars = [
        {"name": "version", "type": "constant", "query": "v4.0.0", "hide": 2},
        {"name": "origin_prometheus", "label": "数据源", "type": "query", "datasource": {"uid": "ds-prometheus"}, "query": "label_values(kube_node_info,origin_prometheus)", "refresh": 1},
        {"name": "NameSpace", "label": "命名空间", "type": "query", "datasource": {"uid": "ds-prometheus"}, "query": "label_values(kube_namespace_created{origin_prometheus=~\"$origin_prometheus\"},namespace)"},
        {"name": "Container", "label": "服务", "description": "服务（容器）", "type": "query", "datasource": {"uid": "ds-prometheus"}, "query": "label_values(kube_pod_container_info{origin_prometheus=~\"$origin_prometheus\",namespace=~\"$NameSpace\"},container)"},
        {"name": "Pod", "label": "Pod", "type": "query", "datasource": {"uid": "ds-prometheus"}, "query": "label_values(kube_pod_container_info{origin_prometheus=~\"$origin_prometheus\",namespace=~\"$NameSpace\",container=~\"$Container\"},pod)"},
        {"name": "hostname", "label": "主机名", "type": "query", "datasource": {"uid": "ds-prometheus"}, "query": "label_values(node_uname_info{origin_prometheus=~\"$origin_prometheus\", job=~\"$job\"},nodename)"},
        {"name": "node", "label": "实例 IP", "type": "query", "datasource": {"uid": "ds-prometheus"}, "query": "label_values(node_uname_info{origin_prometheus=~\"$origin_prometheus\", job=~\"$job\", nodename=~\"$hostname\"},instance)"},
        {"name": "device", "label": "网卡", "type": "query", "datasource": {"uid": "ds-prometheus"}, "query": "label_values(node_network_info{origin_prometheus=~\"$origin_prometheus\", job=~\"$job\", instance=~\"$node\", device!~\"'tap.*|veth.*|br.*|docker.*|virbr.*|lo.*|cni.*'\"},device)"},
        {"name": "interval", "label": "采样间隔", "type": "interval", "query": "3m,5m,10m,30m,1h,6h,12h,1d"},
        {"name": "job", "label": "JOB（高级）", "hide": 2, "type": "query", "datasource": {"uid": "ds-prometheus"}, "query": "label_values(node_uname_info{origin_prometheus=~\"$origin_prometheus\"},job)"},
        {"name": "Node", "label": "节点池（高级）", "hide": 2, "type": "query", "datasource": {"uid": "ds-prometheus"}, "query": "label_values(kube_node_info{origin_prometheus=~\"$origin_prometheus\"},node)"},
        {"name": "maxmount", "hide": 2, "type": "query", "datasource": {"uid": "ds-prometheus"}, "query": "query_result(topk(1,sort_desc(max(node_filesystem_size_bytes{origin_prometheus=~\"$origin_prometheus\",instance=~\"$node\",fstype=~\"ext.?|xfs\",mountpoint!~\".*pods.*\"}) by (mountpoint))))"},
        {"name": "show_hostname", "hide": 2, "type": "query", "datasource": {"uid": "ds-prometheus"}, "query": "label_values(node_uname_info{origin_prometheus=~\"$origin_prometheus\", job=~\"$job\", nodename=~\"$hostname\", instance=~\"$node\"},nodename)"},
        {"name": "total", "hide": 2, "type": "query", "datasource": {"uid": "ds-prometheus"}, "query": "query_result(count(node_uname_info{origin_prometheus=~\"$origin_prometheus\",job=~\"$job\"}))"}
    ]
    homepage["templating"]["list"] = unified_vars

    nav_html = """
<div style="display:flex;justify-content:space-between;align-items:center;gap:16px;flex-wrap:wrap;padding:8px 4px 2px 4px;">
  <div style="display:flex;gap:12px;flex-wrap:wrap;">
    <a href="/d/infra-overview" style="text-decoration:none;padding:10px 16px;border-radius:999px;background:#1f2937;color:#f9fafb;font-weight:700;">基础设施</a>
    <a href="/d/node-overview" style="text-decoration:none;padding:10px 16px;border-radius:999px;background:#e5eefb;color:#1d4ed8;font-weight:700;">主机</a>
    <a href="/d/pgsql-overview" style="text-decoration:none;padding:10px 16px;border-radius:999px;background:#ecfdf3;color:#047857;font-weight:700;">数据库</a>
    <a href="/dashboards" style="text-decoration:none;padding:10px 16px;border-radius:999px;background:#f4f4f5;color:#27272a;font-weight:700;">更多模块</a>
  </div>
  <div style="color:#6b7280;font-size:12px;">先选模块，再用顶部筛选器缩小范围。</div>
</div>
"""

    guide_html = """
<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;padding:4px 2px 0 2px;">
  <div style="border:1px solid #d1d5db;border-radius:12px;padding:12px 14px;background:#fbfdff;">
    <div style="font-size:12px;color:#6b7280;margin-bottom:6px;">范围筛选</div>
    <div style="font-size:14px;font-weight:700;color:#111827;">数据源 → 命名空间 → 服务 → Pod</div>
    <div style="font-size:12px;color:#6b7280;margin-top:6px;">用于缩小 K8S 资源范围</div>
  </div>
  <div style="border:1px solid #d1d5db;border-radius:12px;padding:12px 14px;background:#fbfdff;">
    <div style="font-size:12px;color:#6b7280;margin-bottom:6px;">当前对象</div>
    <div style="font-size:14px;font-weight:700;color:#111827;">主机名 → 实例 IP → 网卡</div>
    <div style="font-size:12px;color:#6b7280;margin-top:6px;">用于定位当前分析对象</div>
  </div>
  <div style="border:1px solid #d1d5db;border-radius:12px;padding:12px 14px;background:#fbfdff;">
    <div style="font-size:12px;color:#6b7280;margin-bottom:6px;">视图参数</div>
    <div style="font-size:14px;font-weight:700;color:#111827;">采样间隔 + 高级筛选</div>
    <div style="font-size:12px;color:#6b7280;margin-top:6px;">JOB 与节点池已折叠为高级项</div>
  </div>
</div>
"""

    top_panels = [
        make_text_panel(1, "模块导航", nav_html, 0, 0, 24, 3),
        make_text_panel(2, "筛选说明", guide_html, 0, 3, 24, 5),
    ]
    homepage["panels"].extend(top_panels)

    current_y = 8
    # 1. Infra
    homepage["panels"].append({"collapsed": False, "gridPos": {"h": 1, "w": 24, "x": 0, "y": current_y}, "title": "基础设施总览", "type": "row", "panels": []})
    current_y += 1
    
    infra_max_y = current_y
    for p in pig.get("panels", []):
        if p.get("type") == "row": continue
        
        # Replace "Apps" panel with "insight Overview" link
        if p.get("title") == "Apps":
            p["title"] = "insight Overview"
            p["type"] = "text"
            p["options"] = {
                "content": "<div style='text-align: center; padding-top: 10px;'><a href='https://observability.svc.plus/insight/' style='font-size: 18px; color: #58a6ff; font-weight: bold;'>insight Overview</a></div>",
                "mode": "html"
            }
        
        shift_panel(p, current_y)
        homepage["panels"].append(p)
        infra_max_y = max(infra_max_y, p["gridPos"]["y"] + p["gridPos"]["h"])
    current_y = infra_max_y

    # 2. Node
    homepage["panels"].append({"collapsed": False, "gridPos": {"h": 1, "w": 24, "x": 0, "y": current_y}, "title": "主机观测", "type": "row", "panels": []})
    current_y += 1
    node_max_y = current_y
    for p in node.get("panels", []):
        shift_panel(p, current_y)
        homepage["panels"].append(p)
        node_max_y = max(node_max_y, p["gridPos"]["y"] + p["gridPos"]["h"])
    current_y = node_max_y

    # 3. K8S
    homepage["panels"].append({"collapsed": False, "gridPos": {"h": 1, "w": 24, "x": 0, "y": current_y}, "title": "K8S 集群", "type": "row", "panels": []})
    current_y += 1
    k8s_max_y = current_y
    for p in k8s.get("panels", []):
        p["gridPos"]["y"] += current_y
        homepage["panels"].append(p)
        k8s_max_y = max(k8s_max_y, p["gridPos"]["y"] + p["gridPos"]["h"])
    current_y = k8s_max_y

    for i, p in enumerate(homepage["panels"]):
        p["id"] = i + 1

    with open(output_path, 'w') as f:
        json.dump(homepage, f, indent=2)

if __name__ == "__main__":
    merge_dashboards()
