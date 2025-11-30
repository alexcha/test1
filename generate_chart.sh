#!/bin/bash

# 이 스크립트는 result.txt 파일을 읽어 HTML 대시보드를 생성합니다.


# 🚨 1. 환경 변수 설정
# GitHub Actions의 ${{ secrets.GKEY }}가 env: GEMINI_API_KEY로 매핑되어 전달됩니다.
GEMINI_API_KEY="$GEMINI_API_KEY" 

if [ -z "$GEMINI_API_KEY" ]; then
    echo "오류: 환경 변수 GEMINI_API_KEY가 설정되지 않았습니다. API 예측은 비활성화됩니다." >&2
fi


# 1. 데이터 파싱: 시간별 변화 값 (JS_VALUES) 및 레이블 (JS_LABELS)
# 변화가 0인 데이터 포인트는 필터링하여 제외합니다.
AWK_SCRIPT_CHANGE_FILTER='
    function format_label(time_str) {
        # YYYY-MM-DD HH:MM:SS -> MM-DD HH시
        return substr(time_str, 6, 5) " " substr(time_str, 12, 2) "시";
    }

    { 
        gsub(/,/, "", $2); 
        all_values[NR] = $2 + 0;
        all_labels[NR] = format_label($1);
    }
    END {
        if (NR == 0) { exit; }
        
        filtered_changes[1] = 0; 
        filtered_labels[1] = all_labels[1];
        filtered_index = 1;
        
        for (i = 2; i <= NR; i++) {
            change = all_values[i] - all_values[i-1];
            
            # 변화가 0이 아닐 경우에만 기록
            if (change != 0) {
                filtered_index++;
                filtered_changes[filtered_index] = change;
                filtered_labels[filtered_index] = all_labels[i];
            } 
        }

        # 변화값 출력 (JS_VALUES)
        for (j = 1; j <= filtered_index; j++) {
            printf "%s", filtered_changes[j]
            if (j < filtered_index) { printf ", " }
        }
        printf "\n"
        
        # 레이블 출력 (JS_LABELS)
        for (j = 1; j <= filtered_index; j++) {
            printf "\"%s\"", filtered_labels[j]
            if (j < filtered_index) { printf ", " }
        }
        printf "\n"
    }
'

# AWK를 한 번 실행하고 결과를 변수에 할당합니다.
AWK_OUTPUT=$(echo -e "$(awk -F ' : ' "$AWK_SCRIPT_CHANGE_FILTER" result.txt)")

# AWK 출력의 첫 번째 줄은 JS_VALUES, 두 번째 줄은 JS_LABELS입니다.
JS_VALUES=$(echo "$AWK_OUTPUT" | head -n 1)
JS_LABELS=$(echo "$AWK_OUTPUT" | tail -n 1)


# 2. 메인 HTML 테이블 ROW 데이터 생성 (RAW_TABLE_ROWS)
# 변화가 0인 항목 제외하고 최신순으로 <tr> 태그 생성
RAW_TABLE_ROWS=$(awk -F ' : ' '
    function comma_format(n) {
        if (n == 0) return "0";
        s = int(n);
        sign = "";
        if (s > 0) { sign = "+"; } 
        else if (s < 0) { sign = "-"; s = -s; }
        
        abs_s_str = s ""; 
        result = "";
        while (abs_s_str ~ /[0-9]{4}/) {
            result = "," substr(abs_s_str, length(abs_s_str)-2) result;
            abs_s_str = substr(abs_s_str, 1, length(abs_s_str)-3);
        }
        return sign abs_s_str result;
    } 

    {
        formatted_time[NR] = substr($1, 6, 5) " " substr($1, 12, 2) "시";
        values_str[NR] = $2;
        gsub(/,/, "", $2); 
        values_num[NR] = $2 + 0; 
    }
    END {
        if (NR == 0) { exit; }
        
        for (i = NR; i >= 1; i--) {
            current_val_num = values_num[i]; 
            diff_display = "---";
            color_style = "color: #6c757d;";
            
            if (i > 1) {
                prev_val_num = values_num[i - 1];
                diff = current_val_num - prev_val_num;
                
                if (diff == 0 && i != 1) { 
                    continue; 
                }
                
                diff_display = comma_format(diff); 
                if (diff > 0) {
                    color_style = "color: #dc3545; font-weight: 600;";
                } else if (diff < 0) {
                    color_style = "color: #007bff; font-weight: 600;";
                } else {
                    color_style = "color: #6c757d;";
                }
            } 

            printf "<tr><td style=\"padding: 8px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white; font-size: 14px; color: #343a40;\">%s</td><td style=\"padding: 8px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; background-color: white; font-weight: 600; color: #333; font-size: 14px;\">%s</td><td style=\"padding: 8px; border-top: 1px solid #eee; text-align: right; background-color: white; font-size: 14px; %s\">%s</td></tr>\n", formatted_time[i], values_str[i], color_style, diff_display
        }
    }
' result.txt) 

# 3. 일별 집계 테이블 및 차트용 데이터 파싱 (DAILY_SUMMARY_TABLE, JS_DAILY_VALUES, JS_DAILY_CHANGES, JS_DAILY_LABELS)
AWK_SCRIPT_DAILY='
    function comma_format_sum_only(n) {
        if (n == 0) return "0";
        s = int(n);
        s_abs = (s < 0) ? -s : s;
        s_str = s_abs ""; 
        result = "";
        while (s_str ~ /[0-9]{4}/) {
            result = "," substr(s_str, length(s_str)-2) result;
            s_str = substr(s_str, 1, length(s_str)-3);
        }
        return (s < 0 ? "-" : "") s_str result;
    }
    
    function comma_format_diff_only(n) {
        if (n == 0) return "0";
        s = int(n);
        sign = "";
        if (s > 0) { sign = "+"; } 
        else if (s < 0) { sign = "-"; s = -s; } 
        else { return "0"; }
        s_abs = (s < 0) ? -s : s;
        s_str = s_abs ""; 
        result = "";
        while (s_str ~ /[0-9]{4}/) {
            result = "," substr(s_str, length(s_str)-2) result;
            s_str = substr(s_str, 1, length(s_str)-3);
        }
        return sign s_str result;
    } 

    {
        numeric_value = $2;
        gsub(/,/, "", numeric_value);
        date = substr($1, 1, 10);
        last_value[date] = numeric_value + 0; 
        if (!(date in added_dates)) {
            dates_arr[num_dates++] = date;
            added_dates[date] = 1;
        }
    }
    END {
        if (num_dates == 0) { 
            print "" > "DAILY_SUMMARY_TABLE";
            print "" > "JS_DAILY_VALUES";
            print "" > "JS_DAILY_CHANGES";
            print "" > "JS_DAILY_LABELS";
            exit; 
        }

        # 날짜 오름차순 정렬
        for (i = 0; i < num_dates; i++) {
            for (j = i + 1; j < num_dates; j++) {
                if (dates_arr[i] > dates_arr[j]) {
                    temp = dates_arr[i];
                    dates_arr[i] = dates_arr[j];
                    dates_arr[j] = temp;
                }
            }
        } 

        # 1. 테이블 생성
        output_table = "<table style=\"width: 100%; border-collapse: separate; border-spacing: 0; border: 1px solid #ddd; font-size: 14px; border-radius: 8px; overflow: hidden; margin-top: 20px; table-layout: fixed;\"><colgroup><col style=\"width: 33%;\"><col style=\"width: 37%;\"><col style=\"width: 30%;\"></colgroup><thead><tr><th style=\"padding: 8px; background-color: white; border-right: 1px solid #ccc; text-align: left; color: #333;\">날짜</th><th style=\"padding: 8px; background-color: white; border-right: 1px solid #ccc; text-align: right; color: #333;\">값</th><th style=\"padding: 8px; background-color: white; text-align: right; color: #333;\">변화</th></tr></thead><tbody>";

        prev_value = 0;
        
        # 값을 계산하면서 배열에 저장
        for (i = 0; i < num_dates; i++) {
            date = dates_arr[i];
            current_value = last_value[date]; 
            diff = current_value - prev_value;
            
            # 차트용 데이터 저장
            daily_values[i] = current_value;
            daily_labels[i] = "\"" date "\"";
            
            # 첫 날의 변화량은 첫 날의 최종값으로 간주
            daily_changes[i] = (i == 0) ? current_value : diff;

            diff_display = "";
            color_style = "";

            if (i == 0) {
                diff_display = "---";
                color_style = "color: #6c757d;"; 
            } else {
                diff_display = comma_format_diff_only(diff);
                if (diff > 0) {
                    color_style = "color: #dc3545; font-weight: 600;";
                } else if (diff < 0) {
                    color_style = "color: #007bff; font-weight: 600;";
                } else {
                    diff_display = "0";
                    color_style = "color: #333; font-weight: 600;";
                }
            }
            
            # 테이블 ROW 저장 (역순 출력을 위해)
            row_data[i] = sprintf("<tr><td style=\"padding: 8px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white; color: #343a40; font-size: 14px;\">%s</td><td style=\"padding: 8px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; background-color: white; font-weight: 600; color: #333; font-size: 14px;\">%s</td><td style=\"padding: 8px; border-top: 1px solid #eee; text-align: right; background-color: white; font-size: 14px; %s\">%s</td></tr>", date, comma_format_sum_only(current_value), color_style, diff_display); 

            prev_value = current_value;
        } 

        # 테이블 출력 (최신순으로 역순 출력)
        for (i = num_dates - 1; i >= 0; i--) {
            output_table = output_table row_data[i];
        } 
        output_table = output_table "</tbody></table>";
        print output_table > "DAILY_SUMMARY_TABLE";

        # 2. JS_DAILY_VALUES 출력
        for (i = 0; i < num_dates; i++) {
            printf "%s", daily_values[i] > "JS_DAILY_VALUES";
            if (i < num_dates - 1) { printf ", " > "JS_DAILY_VALUES"; }
        }
        
        # 3. JS_DAILY_CHANGES 출력
        for (i = 0; i < num_dates; i++) {
            printf "%s", daily_changes[i] > "JS_DAILY_CHANGES";
            if (i < num_dates - 1) { printf ", " > "JS_DAILY_CHANGES"; }
        }
        
        # 4. JS_DAILY_LABELS 출력
        for (i = 0; i < num_dates; i++) {
            printf "%s", daily_labels[i] > "JS_DAILY_LABELS";
            if (i < num_dates - 1) { printf ", " > "JS_DAILY_LABELS"; }
        }
    }
'

# AWK를 한 번 실행하여 여러 파일을 생성
awk -F ' : ' "$AWK_SCRIPT_DAILY" result.txt

# 생성된 파일의 내용을 변수에 로드
DAILY_SUMMARY_TABLE=$(cat DAILY_SUMMARY_TABLE 2>/dev/null)
JS_DAILY_VALUES=$(cat JS_DAILY_VALUES 2>/dev/null)
JS_DAILY_CHANGES=$(cat JS_DAILY_CHANGES 2>/dev/null)
JS_DAILY_LABELS=$(cat JS_DAILY_LABELS 2>/dev/null)

# 임시 파일 정리
rm -f DAILY_SUMMARY_TABLE JS_DAILY_VALUES JS_DAILY_CHANGES JS_DAILY_LABELS

# 4. AI 예측용 원본 데이터 문자열
RAW_DATA_PROMPT_CONTENT=$(awk '
    {
        gsub(/"/, "\\\"", $0);
        output = output $0 "\\n";
    }
    END {
        sub(/\\n$/, "", output);
        print output;
    }
' result.txt)


# --- 5. AI 예측 로직 (API 호출) ---

MODEL="gemini-2.5-flash"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI_API_KEY}"

# 날짜 계산
LAST_DATA_DATE=$(tail -n 1 result.txt | awk -F ' : ' '{print $1}' | cut -d ' ' -f 1 2>/dev/null)
TARGET_DATE=""
END_OF_MONTH_DATE=""

if [ -n "$LAST_DATA_DATE" ]; then
    TARGET_DATE=$(date -d "$LAST_DATA_DATE + 1 day" +%Y-%m-%d 2>/dev/null)
    YEAR_MONTH=$(date -d "$LAST_DATA_DATE" +%Y-%m 2>/dev/null)
    END_OF_MONTH_DATE=$(date -d "$YEAR_MONTH-01 + 1 month - 1 day" +%Y-%m-%d 2>/dev/null)
fi

# JSON 페이로드에 들어갈 내용을 이스케이프하는 함수
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;s/\n/\\n/g;ta'
}

PREDICTION_HEADER_EMBED="AI 기반 추이 분석 및 예측"
PREDICTION_TEXT_EMBED='<div class="error-message"><span style="font-weight: 700;">⚠️ 오류: API 키 없음.</span> 환경 변수 GEMINI_API_KEY가 설정되지 않아 예측을 실행할 수 없습니다.</div>' 

if [ -n "$GEMINI_API_KEY" ] && [ -n "$TARGET_DATE" ] && [ -n "$RAW_DATA_PROMPT_CONTENT" ]; then
    SYSTEM_PROMPT="**핵심 고려 사항: CONTEXTUAL_PRIORITY**\n**데이터 맥락: 분석하는 데이터는 10월 28일에 오픈한 모바일 게임의 누적 매출 데이터입니다. https://raw.githubusercontent.com/alexcha/alexcha.github.io/refs/heads/main/11.result.txt 는 11월의 매출 데이터 입니다. (단위: 달러)**\n\n당신은 전문 데이터 분석가입니다. 제공된 시계열 누적 데이터를 분석하고, 다음 세 가지 핵심 정보를 포함하여 **최대 3문장 이내**로 응답하세요: 1) **현재 일별 변화 추이(상승, 하락, 횡보)**, 2) **다음 날(${TARGET_DATE})의 예상 최종 누적 값**, 3) **이달 말(${END_OF_MONTH_DATE})의 예상 최종 누적 값**. 불필요한 서론/결론, 목록, 표는 절대 포함하지 마세요. 추정치임을 명시해야 합니다."
    USER_QUERY="다음은 시계열 누적 데이터입니다. 이 데이터를 분석하여 **${TARGET_DATE}**와 **${END_OF_MONTH_DATE}**의 예상 누적 값을 예측해주세요.\\n\\n데이터:\\n${RAW_DATA_PROMPT_CONTENT}"

    JSON_SYSTEM_PROMPT=$(escape_json "$SYSTEM_PROMPT")
    JSON_USER_QUERY=$(escape_json "$USER_QUERY")

    PAYLOAD='{
        "contents": [{ "parts": [{ "text": "'"$JSON_USER_QUERY"'" }] }],
        "systemInstruction": { "parts": [{ "text": "'"$JSON_SYSTEM_PROMPT"'" }] },
        "tools": [{ "google_search": {} }]
    }'

    API_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -H "Accept: application/json" "$API_URL" -d "$PAYLOAD" 2>/dev/null)
    CURL_STATUS=$?

    if [ $CURL_STATUS -eq 0 ]; then
        RAW_TEXT_CONTENT=$(echo "$API_RESPONSE" | jq -r '.candidates[0].content.parts[0].text // ""' 2>/dev/null)
        
        if [ -n "$RAW_TEXT_CONTENT" ]; then
            PREDICTION_HEADER_EMBED="AI 기반 추이 분석 및 예측: ${TARGET_DATE} 및 ${END_OF_MONTH_DATE}"
            FORMATTED_TEXT=$(echo "$RAW_TEXT_CONTENT" | sed ':a;N;$!ba;s/\n/<br>/g' | sed 's/\t/&nbsp;&nbsp;&nbsp;&nbsp;/g')
            PREDICTION_TEXT_EMBED="<div class=\"success-message\">${FORMATTED_TEXT}</div>"
        else
            ERROR_MESSAGE=$(echo "$API_RESPONSE" | grep -o '"message": "[^"]*"' | head -n 1 | sed 's/"message": "//; s/"$//')
            BLOCK_REASON=$(echo "$API_RESPONSE" | jq -r '.candidates[0].finishReason // .promptFeedback.blockReason // ""' 2>/dev/null)
            
            if [ -n "$ERROR_MESSAGE" ]; then
                PREDICTION_TEXT_EMBED="<div class=\"error-message\"><span style=\"font-weight: 700;\">⚠️ 예측 결과 실패.</span> API 오류: ${ERROR_MESSAGE}</div>"
            elif [ -n "$BLOCK_REASON" ]; then
                PREDICTION_TEXT_EMBED="<div class=\"error-message\"><span style=\"font-weight: 700;\">⚠️ 응답 필터링됨.</span> 응답 내용이 정책에 의해 차단되었거나 누락되었습니다. (Reason: ${BLOCK_REASON})</div>"
            else
                PREDICTION_TEXT_EMBED="<div class=\"error-message\"><span style=\"font-weight: 700;\">⚠️ 응답 파싱 실패.</span> 예측 텍스트를 파싱할 수 없습니다.</div>"
            fi
        fi
    else
        PREDICTION_TEXT_EMBED="<div class=\"error-message\"><span style=\"font-weight: 700;\">❌ API 호출 실패.</span> Curl 상태 코드: $CURL_STATUS. 네트워크 연결을 확인하세요.</div>"
    fi
fi


# ⭐️⭐️⭐️ 6. 디버깅 출력 ⭐️⭐️⭐️
echo "--- AWK 파싱 결과 디버깅 정보 ---"
echo "1. JS_VALUES (시간별 변화 값): [${JS_VALUES}]"
echo "2. JS_DAILY_VALUES (일별 최종 값 - 누적): [${JS_DAILY_VALUES}]"
echo "3. JS_DAILY_CHANGES (일별 변화량): [${JS_DAILY_CHANGES}]"
echo "4. RAW_TABLE_ROWS (시간별 기록 TR 태그):"
echo "${RAW_TABLE_ROWS}"
echo "--------------------------------------------------------"

# 7. HTML 파일 생성 (H2 태그 제거)
cat << CHART_END > money.html
<!DOCTYPE html>
<html>
<head>
    <title>데이터 변화 추이 대시보드</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js"></script>
    <style>
        /* CSS 스타일... (생략 - 이전과 동일) */
        body { font-family: 'Inter', sans-serif; margin: 0; padding: 0; background-color: #f7f7f7; color: #333; }
        .container { width: 95%; max-width: 1400px; margin: 0 auto; padding: 10px; background: white; border-radius: 0; box-shadow: none; }
        h1 { text-align: center; color: #333; margin-bottom: 5px; font-size: 26px; font-weight: 700; }
        p.update-time { text-align: center; color: #777; margin-bottom: 20px; font-size: 14px; }
        .chart-container { margin-bottom: 30px; border: 1px solid #eee; border-radius: 8px; padding: 15px; background: #fff; height: 40vh; min-height: 300px; box-shadow: 0 4px 8px rgba(0, 0, 0, 0.05); position: relative; }
        /* 이 부분의 H2 스타일은 차트 제목 대신 테이블 제목에만 적용되도록 남겨둡니다. */
        h2 { margin-top: 30px; margin-bottom: 10px; text-align: center; color: #343a40; font-size: 22px; font-weight: 600; border-bottom: 2px solid #343a40; padding-bottom: 8px; display: inline-block; width: auto; margin-left: auto; margin-right: auto; }
        #daily-chart-header, #daily-change-chart-header, #daily-summary-chart-header { margin-top: 40px !important; }
        .prediction-section { padding: 20px; margin-bottom: 30px; background-color: #f0f8ff; border: 2px solid #007bff; border-radius: 12px; text-align: center; }
        .prediction-section h2 { color: #0056b3; margin-top: 0; border-bottom: none; padding-bottom: 0; font-size: 24px; }
        .error-message { text-align: left; padding: 15px; background-color: #ffe0e6; border: 1px solid #dc3545; color: #dc3545; border-radius: 8px; line-height: 1.6; font-size: 15px; margin-top: 20px; }
        .success-message { text-align: left; padding: 15px; background-color: white; border: 1px solid #ccc; border-radius: 8px; min-height: 50px; font-size: 15px; line-height: 1.6; margin-top: 20px; color: #333; }
        .sources-container { margin-top: 20px; border-top: 1px solid #eee; padding-top: 10px; }
        .no-data-message { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); text-align: center; color: #6c757d; padding: 20px; font-size: 16px; font-weight: 600; width: 80%; }
        .pagination-controls { display: flex; justify-content: center; align-items: center; margin-top: 15px; margin-bottom: 40px; gap: 10px; }
        .pagination-button { background-color: #007bff; color: white; border: none; padding: 8px 15px; border-radius: 6px; cursor: pointer; transition: background-color 0.2s, opacity 0.2s; font-weight: 600; }
        .pagination-button:hover:not(:disabled) { background-color: #0056b3; }
        .pagination-button:disabled { background-color: #ccc; cursor: not-allowed; opacity: 0.6; }
        .page-info { font-weight: 600; color: #555; font-size: 15px; }
        .data-table-wrapper { width: 100%; margin: 0 auto; border-collapse: separate; border-spacing: 0; border: 1px solid #ddd; border-radius: 8px; overflow-x: auto; -webkit-overflow-scrolling: touch; }
        .data-table-wrapper table { width: 100%; table-layout: fixed; border: none; }
    </style>
</head>
<body>
    <div class="container">
        <p class="update-time">최근 업데이트 시간: $(tail -n 1 result.txt | awk -F ' : ' '{print $1}')</p>
        
        <div class="prediction-section">
            <h2 id="prediction-header">${PREDICTION_HEADER_EMBED}</h2>
            <div id="predictionResult">
                ${PREDICTION_TEXT_EMBED}
            </div>
        </div>
        
        <div class="chart-container">
            <canvas id="dailyChart"></canvas>
            <p id="dailyChartNoData" class="no-data-message" style="display: none;">일일 집계 데이터가 없어 차트를 그릴 수 없습니다.</p>
        </div>
        
        <div class="chart-container">
            <canvas id="dailyChangeChart"></canvas>
            <p id="dailyChangeChartNoData" class="no-data-message" style="display: none;">일일 변화량 데이터가 없어 차트를 그릴 수 없습니다.</p>
        </div>
        
        <div style="text-align: center;">
            <h2 id="daily-summary-chart-header">일일 집계 기록 (요약 테이블)</h2>
        </div>
        <div class="data-table-wrapper">
            ${DAILY_SUMMARY_TABLE}
        </div> 
        
        <div class="chart-container">
            <canvas id="simpleChart"></canvas>
            <p id="simpleChartNoData" class="no-data-message" style="display: none;">데이터가 없어 차트를 그릴 수 없습니다.</p>
        </div> 

        
        <div style="text-align: center;">
            <h2>데이터 기록 (시간별 - 최신순)</h2>
        </div>
        
        <div id="dataRecordsContainer">
            </div>
        <div id="paginationControls" class="pagination-controls">
            </div>
        
    </div>
    
    <script>
    // 🚨 셸 스크립트에서 파싱된 동적 데이터가 여기에 삽입됩니다.
    
    // 1. 시간별 변화 데이터
    const chartData = [${JS_VALUES}];
    const chartLabels = [${JS_LABELS}]; 

    // 2. 일별 최종 값 데이터 (누적)
    const jsDailyValues = [${JS_DAILY_VALUES}]; 
    const jsDailyLabels = [${JS_DAILY_LABELS}]; 
    
    // 3. 일별 변화량 데이터
    const jsDailyChanges = [${JS_DAILY_CHANGES}];

    // 4. 페이지네이션을 위한 전체 ROW 데이터
    const rawRowData = \`
${RAW_TABLE_ROWS}
\`.trim().split('\\n').filter(row => row.trim() !== '');

    const ROWS_PER_PAGE = 20;
    let currentPage = 1;
    const totalPages = Math.ceil(rawRowData.length / ROWS_PER_PAGE);

    // --- 페이지네이션 로직 ---

    function getPageRows(page) {
        const start = (page - 1) * ROWS_PER_PAGE;
        const end = start + ROWS_PER_PAGE;
        return rawRowData.slice(start, end);
    }

    function renderTable(page) {
        const rows = getPageRows(page);
        const container = document.getElementById('dataRecordsContainer');
        
        const tableHtml = \`
            <div class="data-table-wrapper">
            <table style="width: 100%; border-collapse: separate; border-spacing: 0; table-layout: fixed; font-size: 13px;">
                <colgroup>
                    <col style="width: 33%;"> 
                    <col style="width: 37%;"> 
                    <col style="width: 30%;"> 
                </colgroup>
                <thead>
                    <tr>
                        <th style="padding: 8px; background-color: white; border-right: 1px solid #ccc; text-align: left; color: #333;">시간</th>
                        <th style="padding: 8px; background-color: white; border-right: 1px solid #ccc; text-align: right; color: #333;">값</th>
                        <th style="padding: 8px; background-color: white; text-align: right; color: #333;">변화</th>
                    </tr>
                </thead>
                <tbody>
                    \${rows.join('')}
                </tbody>
            </table>
            </div>
        \`;

        container.innerHTML = tableHtml;
        renderPaginationControls();
    }

    function renderPaginationControls() {
        const controlsContainer = document.getElementById('paginationControls');
        
        if (totalPages <= 1) {
            controlsContainer.innerHTML = '';
            return;
        }

        controlsContainer.innerHTML = \`
            <button class="pagination-button" onclick="goToPage(1)" \${currentPage === 1 ? 'disabled' : ''}>
                &lt;&lt; 처음
            </button>
            <button class="pagination-button" onclick="goToPage(\${currentPage - 1})" \${currentPage === 1 ? 'disabled' : ''}>
                &lt; 이전
            </button>
            <span class="page-info">\${currentPage} / \${totalPages} 페이지</span>
            <button class="pagination-button" onclick="goToPage(\${currentPage + 1})" \${currentPage === totalPages ? 'disabled' : ''}>
                다음 &gt;
            </button>
            <button class="pagination-button" onclick="goToPage(\${totalPages})" \${currentPage === totalPages ? 'disabled' : ''}>
                마지막 &gt;&gt;
            </button>
        \`;
    }

    window.goToPage = function(page) {
        if (page >= 1 && page <= totalPages && page !== currentPage) {
            currentPage = page;
            renderTable(currentPage);
            document.getElementById('dataRecordsContainer').scrollIntoView({ behavior: 'smooth' });
        }
    };
    
    if (rawRowData.length > 0) {
        renderTable(currentPage);
    } else {
        document.getElementById('dataRecordsContainer').innerHTML = "<p class='no-data-message'>데이터 기록이 존재하지 않습니다.</p>";
        document.getElementById('paginationControls').innerHTML = '';
    }

    // --- 차트 공통 함수 ---
    const formatYAxisTick = function(value) {
        if (value === 0) return '0';
        
        const absValue = Math.abs(value);
        let formattedValue; 

        if (absValue >= 1000000000) {
            formattedValue = (value / 1000000000).toFixed(1).replace(/\\.0$/, '') + 'B';
        } else if (absValue >= 1000000) {
            formattedValue = (value / 1000000).toFixed(1).replace(/\\.0$/, '') + 'M';
        } else if (absValue >= 1000) {
            formattedValue = (value / 1000).toFixed(1).replace(/\\.0$/, '') + 'K';
        } else {
            formattedValue = new Intl.NumberFormat('ko-KR', { maximumFractionDigits: 0 }).format(value);
        }
        return formattedValue;
    };
    
    const formatTooltip = function(context) {
        let label = context.dataset.label || '';
        if (label) { label += ': '; }
        if (context.parsed.y !== null) {
            // JS Chart.js title을 변경했으므로, 툴팁 포맷은 dataset.label을 기반으로 결정
            // title을 제거했으므로, 차트 이름에 직접 "변화" 또는 "누적"을 포함해야 합니다.
            const chartId = context.chart.canvas.id;
            const isChangeValue = chartId.includes('Change') || chartId.includes('simple'); 
            label += new Intl.NumberFormat('ko-KR', { signDisplay: isChangeValue ? 'always' : 'auto', maximumFractionDigits: 0 }).format(context.parsed.y);
        }
        return label;
    };


    // ---------------------------------------------
    // 1. 시간별 변화 값 추이 (simpleChart)
    // --------------------------------------------- 
    const simpleChartCanvas = document.getElementById('simpleChart');
    if (chartData.length === 0) {
        simpleChartCanvas.style.display = 'none';
        document.getElementById('simpleChartNoData').style.display = 'block';
    } else {
        document.getElementById('simpleChartNoData').style.display = 'none';
        new Chart(simpleChartCanvas.getContext('2d'), {
            type: 'line', 
            data: {
                labels: chartLabels,
                datasets: [{
                    label: '시간별 변화 값', 
                    data: chartData,
                    borderColor: 'rgba(255, 99, 132, 1)',
                    backgroundColor: 'rgba(255, 99, 132, 0.4)', 
                    borderWidth: 1, 
                    tension: 0.4,
                    pointRadius: 1, 
                    pointBackgroundColor: 'rgba(255, 99, 132, 1)', 
                    pointHoverRadius: 3, 
                    fill: 'start'
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: {
                        type: 'category', 
                        title: { display: true, text: '시간', font: { size: 14, weight: 'bold' } }, 
                        ticks: {
                            maxRotation: 45, minRotation: 45, autoSkip: true, maxTicksLimit: 15, font: { size: 12 }
                        }
                    },
                    y: {
                        title: { display: true, text: '변화 값', font: { size: 14, weight: 'bold' } }, 
                        beginAtZero: true, 
                        grid: { color: 'rgba(0, 0, 0, 0.05)' },
                        ticks: { callback: formatYAxisTick }
                    }
                },
                plugins: {
                    legend: { display: true }, // 범례를 보여주어 차트 제목 역할을 대체
                    tooltip: { mode: 'index', intersect: false, bodyFont: { size: 14 }, callbacks: { label: formatTooltip } },
                    title: { display: false } // 제목 제거
                }
            }
        });
    } 

    // ---------------------------------------------
    // 2. 일일 최종 누적 값 추이 (dailyChart)
    // ---------------------------------------------
    const dailyChartCanvas = document.getElementById('dailyChart');
    if (jsDailyValues.length === 0) {
        dailyChartCanvas.style.display = 'none';
        document.getElementById('dailyChartNoData').style.display = 'block';
    } else {
        document.getElementById('dailyChartNoData').style.display = 'none';
        new Chart(dailyChartCanvas.getContext('2d'), {
            type: 'line',
            data: {
                labels: jsDailyLabels,
                datasets: [{
                    label: '일일 최종 값 (누적)',
                    data: jsDailyValues,
                    borderColor: 'rgba(0, 123, 255, 1)',
                    backgroundColor: 'rgba(0, 123, 255, 0.2)', 
                    borderWidth: 4, tension: 0.3, pointRadius: 6, pointBackgroundColor: 'rgba(0, 123, 255, 1)', pointHoverRadius: 8, fill: 'start' 
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: {
                        type: 'category', 
                        title: { display: true, text: '날짜', font: { size: 14, weight: 'bold' } },
                        ticks: { font: { size: 12 }, maxRotation: 45, minRotation: 45 }
                    },
                    y: {
                        title: { display: true, text: '최종 누적 값', font: { size: 14, weight: 'bold' } },
                        beginAtZero: false,
                        grid: { color: 'rgba(0, 0, 0, 0.05)' },
                        ticks: { callback: formatYAxisTick }
                    }
                },
                plugins: {
                    legend: { display: true }, // 범례를 보여주어 차트 제목 역할을 대체
                    tooltip: { mode: 'index', intersect: false, bodyFont: { size: 14 }, callbacks: { label: formatTooltip } },
                    title: { display: false } // 제목 제거
                }
            }
        });
    }

    // ---------------------------------------------
    // 3. 일일 변화량 추이 (dailyChangeChart)
    // ---------------------------------------------
    const dailyChangeChartCanvas = document.getElementById('dailyChangeChart');
    if (jsDailyChanges.length === 0) {
        dailyChangeChartCanvas.style.display = 'none';
        document.getElementById('dailyChangeChartNoData').style.display = 'block';
    } else {
        document.getElementById('dailyChangeChartNoData').style.display = 'none';
        new Chart(dailyChangeChartCanvas.getContext('2d'), {
            type: 'bar', 
            data: {
                labels: jsDailyLabels,
                datasets: [{
                    label: '일일 변화량',
                    data: jsDailyChanges,
                    backgroundColor: function(context) {
                        const value = context.parsed.y;
                        if (value > 0) { return 'rgba(220, 53, 69, 0.8)'; } // Red (상승)
                        else if (value < 0) { return 'rgba(0, 123, 255, 0.8)'; } // Blue (하락)
                        else { return 'rgba(108, 117, 125, 0.8)'; } // Gray (변화 없음)
                    },
                    borderColor: function(context) {
                        const value = context.parsed.y;
                        if (value > 0) { return 'rgba(220, 53, 69, 1)'; }
                        else if (value < 0) { return 'rgba(0, 123, 255, 1)'; }
                        else { return 'rgba(108, 117, 125, 1)'; }
                    },
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: {
                        type: 'category', 
                        title: { display: true, text: '날짜', font: { size: 14, weight: 'bold' } },
                        ticks: { font: { size: 12 }, maxRotation: 45, minRotation: 45 }
                    },
                    y: {
                        title: { display: true, text: '변화량', font: { size: 14, weight: 'bold' } },
                        beginAtZero: true, 
                        grid: { color: 'rgba(0, 0, 0, 0.05)' },
                        ticks: { callback: formatYAxisTick }
                    }
                },
                plugins: {
                    legend: { display: true }, // 범례를 보여주어 차트 제목 역할을 대체
                    tooltip: { mode: 'index', intersect: false, bodyFont: { size: 14 }, callbacks: { label: formatTooltip } },
                    title: { display: false } // 제목 제거
                }
            }
        });
    }
    </script>
</body>
</html>
CHART_END
