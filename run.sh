#!/bin/bash

# GCloud Load Balancer 類型掃描腳本
# 用於掃描和分類 Google Cloud Load Balancer

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 偵錯模式 (設為 true 可以看到詳細判斷過程)
DEBUG_MODE=false

# 檢查是否已安裝 gcloud
check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        echo -e "${RED}錯誤: gcloud CLI 未安裝或不在 PATH 中${NC}"
        exit 1
    fi
}

# 檢查是否已登入 gcloud
check_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        echo -e "${RED}錯誤: 請先使用 'gcloud auth login' 登入${NC}"
        exit 1
    fi
}

# 檢查是否安裝 jq
check_jq() {
if ! command -v jq &> /dev/null; then
    echo -e "${RED}錯誤: 需要安裝 jq 來解析 JSON${NC}"
    echo "請使用 Homebrew 安裝: brew install jq"
    exit 1
fi
}

# 偵錯輸出函數
debug_print() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo -e "${CYAN}[DEBUG] $1${NC}" >&2
    fi
}

# 判斷 Load Balancer 類型
determine_lb_type() {
    local project_id="$1"
    local name="$2"
    local region="$3"
    local global_flag="$4"

    local describe_cmd
    if [[ "$global_flag" == "true" ]]; then
        describe_cmd="gcloud compute forwarding-rules describe $name --global --project=$project_id --format=json"
    else
        describe_cmd="gcloud compute forwarding-rules describe $name --region=$region --project=$project_id --format=json"
    fi

    local rule_info
    if ! rule_info=$($describe_cmd 2>/dev/null); then
        echo "Unknown - 無法獲取詳細資訊"
        return
    fi

    local load_balancing_scheme=$(echo "$rule_info" | jq -r '.loadBalancingScheme // "EXTERNAL"')
    local ip_protocol=$(echo "$rule_info" | jq -r '.IPProtocol // ""')
    local target=$(echo "$rule_info" | jq -r '.target // ""')
    local backend_service=$(echo "$rule_info" | jq -r '.backendService // ""')
    local port_range=$(echo "$rule_info" | jq -r '.portRange // ""')
    local all_ports=$(echo "$rule_info" | jq -r '.allPorts // false')
    local network_tier=$(echo "$rule_info" | jq -r '.networkTier // ""')
    local ports=$(echo "$rule_info" | jq -r '.ports // []')

    debug_print "Rule: $name"
    debug_print "Global: $global_flag, Region: $region"
    debug_print "LoadBalancingScheme: $load_balancing_scheme"
    debug_print "Target: $target"
    debug_print "BackendService: $backend_service"
    debug_print "NetworkTier: $network_tier"
    debug_print "IPProtocol: $ip_protocol"
    debug_print "PortRange: $port_range"
    debug_print "AllPorts: $all_ports"

    local lb_type="Unknown"

    if [[ "$global_flag" == "true" ]]; then
        case "$load_balancing_scheme" in
            "EXTERNAL")
                if [[ "$target" == *"targetHttpProxies"* || "$target" == *"targetHttpsProxies"* ]];then
                    lb_type="Classic Application Load Balancer"
                fi
                if [[ "$target" == *"targetTcpProxies"* || "$target" == *"targetSslProxies"* ]]; then
                    lb_type="Classic Proxy Network Load Balancer"
                fi
                ;;
            "EXTERNAL_MANAGED")
                if [[ "$target" == *"targetHttpProxies"* || "$target" == *"targetHttpsProxies"* ]];then
                    lb_type="Global external Application Load Balancer"
                fi
                if [[ "$target" == *"targetTcpProxies"* || "$target" == *"targetSslProxies"* ]]; then
                    lb_type="Global external Proxy Network Load Balancer"
                fi
                ;;
            "INTERNAL_MANAGED")
                if [[ "$target" == *"targetHttpProxies"* || "$target" == *"targetHttpsProxies"* ]]; then
                    lb_type="Cross-Region internal Application Load Balancer"
                fi
                if [[ "$target" == *"targetTcpProxies"* || "$target" == *"targetSslProxies"* ]]; then
                    lb_type="Cross-Region internal Proxy Network Load Balancer"
                fi
                ;;
        esac
    else
        case "$load_balancing_scheme" in
            "EXTERNAL")
                if [[ "$target" == *"targetPool"* || "$all_ports" == "true" ]]; then
                    lb_type="External passthrough Network Load Balancer (Target-pool Network Load Balancer)"
                fi
                # 新增判斷：target 為空且 backendService 有值且 IPProtocol 為 TCP/UDP
                if [[ -z "$target" && -n "$backend_service" && ( "$ip_protocol" == "TCP" || "$ip_protocol" == "UDP" ) ]]; then
                    lb_type="External passthrough Network Load Balancer"
                fi
                ;;
            "EXTERNAL_MANAGED")
                if [[ "$target" == *"targetHttpProxies"* ]] || [[ "$target" == *"targetHttpsProxies"* ]]; then
                    lb_type="Regional external Application Load Balancer"
                fi
                if [[ "$target" == *"targetTcpProxies"* || "$target" == *"targetSslProxies"* ]]; then
                    lb_type="Regional external Proxy Network Load Balancer"
                fi
                ;;
            "INTERNAL")
                lb_type="Internal passthrough Network Load Balancer"
                ;;
            "INTERNAL_MANAGED")
                if [[ "$target" == *"targetHttpProxies"* || "$target" == *"targetHttpsProxies"* ]]; then
                    lb_type="Regional internal Application Load Balancer"
                fi
                if [[ "$target" == *"targetTcpProxies"* || "$target" == *"targetSslProxies"* ]]; then
                    lb_type="Regional internal Proxy Network Load Balancer"
                fi
                ;;
        esac
    fi

    echo "$lb_type"
}

# 主函數
main() {
    echo -e "${BLUE}=== Google Cloud Load Balancer 掃描工具 ===${NC}\n"
    check_gcloud
    check_auth
    check_jq

    local project_id
    if [[ -n "$1" ]]; then
        project_id="$1"
    else
        project_id=$(gcloud config get-value project 2>/dev/null)
        if [[ -z "$project_id" ]]; then
            echo -e "${RED}錯誤: 未設定 GCP 項目${NC}"
            echo "請使用: gcloud config set project YOUR_PROJECT_ID"
            exit 1
        fi
    fi

    echo -e "${GREEN}當前項目: $project_id${NC}\n"
    echo -e "${YELLOW}正在掃描 forwarding rules...${NC}"

    local global_rules
    global_rules=$(gcloud compute forwarding-rules list --global --project=$project_id --format="value(name,IP_ADDRESS)" 2>/dev/null || true)
    local regional_rules
    regional_rules=$(gcloud compute forwarding-rules list --filter="region:*" --project=$project_id --format="value(name,region,IP_ADDRESS)" 2>/dev/null || true)

    echo -e "\n${CYAN}=== Load Balancer 分析結果 ===${NC}\n"

    local count=0

    # Global Rules
    if [[ -n "$global_rules" ]]; then
        while IFS=$'\t' read -r rule_name ip_address; do
            [[ -z "$rule_name" || -z "$ip_address" ]] && continue
            ((count++))
            echo -e "${PURPLE}[$count] Global Forwarding Rule: $rule_name${NC}"
            lb_type=$(determine_lb_type "$project_id" "$rule_name" "" "true")
            echo -e "類型: ${GREEN}$lb_type${NC}"
            echo -e "IP： ${YELLOW}$ip_address${NC}\n"
        done <<< "$global_rules"
    fi

    # Regional Rules
    if [[ -n "$regional_rules" ]]; then
        while IFS=$'\t' read -r rule_name region ip_address; do
            [[ -z "$rule_name" || -z "$region" || -z "$ip_address" ]] && continue
            ((count++))
            echo -e "${PURPLE}[$count] Regional Forwarding Rule: $rule_name${NC}"
            lb_type=$(determine_lb_type "$project_id" "$rule_name" "$region" "false")
            echo -e "類型: ${GREEN}$lb_type${NC}"
            echo -e "IP： ${YELLOW}$ip_address${NC}\n"
        done <<< "$regional_rules"
    fi

    if [[ $count -eq 0 ]]; then
        echo -e "${YELLOW}在項目 $project_id 中未找到任何 Load Balancer${NC}"
    else
        echo -e "${GREEN}總共找到 $count 個 Load Balancer${NC}"
    fi
}

# 執行主函數
main "$@"