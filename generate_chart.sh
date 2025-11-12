#!/bin/bash
# 이 스크립트는 데이터 추출, 계산, 그리고 HTML 대시보드 생성까지 모두 처리합니다.



# 🚨 TZ 환경 변수를 'Asia/Seoul'로 설정하여 date 명령이 정확히 KST를 출력하도록 강제합니다.
export TZ='Asia/Seoul'

# 1. 데이터 추출 및 계산 로직 시작 (사용자 제공 스크립트 기반)
# ----------------------------------------------------------------

# 1.1. 스크립트 실행 시간 획득 (이제 정확히 KST 시간이 출력됩니다)
EXEC_TIME=$(date '+%Y-%m-%d %H:%M:%S KST')

# 1.2. 상수 정의
URL="https://sss.wemixplay.com/en/lygl?wmsso_sign=check"
CONSTANT_VALUE=50000
MULTIPLIER=100

# 1.3. 데이터 가져오기 및 타겟 라인 추출
TARGET_LINE=$(curl -s "$URL" | html2text | grep 'WEMIX = \$')

# 1.4. WEMIX 총액 (A) 추출 및 정제
# WEMIX = $48,918 (0.5672)와 같은 패턴에서 $48,918을 추출
A_RAW=$(echo "$TARGET_LINE" | grep -o 'WEMIX = \$[0-9,]*' | sed -E 's/WEMIX = \$//')
A_NUM=$(echo "$A_RAW" | tr -d ',' | tr -d ' ' | tr -d '$') # 쉼표, 공백, $ 기호 모두 제거

# 1.5. WEMIX 단가 (B) 추출 및 정제 (예: $0.5672)
# 패턴: WEMIX = $48,918 (0.5672)
B_RAW=$(echo "$TARGET_LINE" | grep -o '([0-9.]\+)' | tr -d '()')
B_NUM=$(echo "$B_RAW" | tr -d '$')

# 1.6. 필수 값 누락 확인 (오류 방지)
if [ -z "$A_NUM" ] || [ -z "$B_NUM" ]; then
    echo "오류: 유동적인 두 값을 모두 추출하지 못했습니다. (A_NUM: '$A_NUM', B_NUM: '$B_NUM')" >&2
    # 데이터를 추출하지 못했으므로, result.txt에 최소한의 오류 레코드를 남기고 스크립트 종료
    echo "$EXEC_TIME : 0" >> result.txt 
    exit 1
fi

# 1.7. 계산 (bc 사용)
CALC_EXPRESSION="$A_NUM - ($CONSTANT_VALUE * $B_NUM)"
FINAL_CALC_EXPRESSION="($CALC_EXPRESSION) * $MULTIPLIER"

# scale=0: 소수점 이하를 표시하지 않습니다.
RESULT=$(echo "scale=0; $FINAL_CALC_EXPRESSION / 1" | bc)

# 1.8. 최종 결과 포맷팅 (쉼표 추가)
if [ "$RESULT" -lt 0 ]; then
    ABS_RESULT=$(echo "$RESULT" | tr -d '-')
    FINAL_RESULT_FORMATTED="-$(echo "$ABS_RESULT" | sed -E ':a;s/^([0-9]+)([0-9]{3})/\1,\2/;ta')"
else
    FINAL_RESULT_FORMATTED=$(echo "$RESULT" | sed -E ':a;s/^([0-9]+)([0-9]{3})/\1,\2/;ta')
fi

# 1.9. 최종 출력 및 result.txt에 기록
echo "$EXEC_TIME : $FINAL_RESULT_FORMATTED" >> result.txt


# 2. HTML 대시보드 생성 로직 시작
# ----------------------------------------------------------------

# 🚨 환경 변수 설정 (GitHub Actions 환경 변수 이름과 일치시킴)
# GitHub Actions의 ${{ secrets.GKEY }}가 env: GEMINI_API_KEY로 매핑되어 전달됩니다.
GEMINI_API_KEY="$GEMINI_API_KEY" 

# 오류 체크: API 키가 비어있는지 셸에서 사전 체크
if [ -z "$GEMINI_API_KEY" ]; then
    echo "오류: 환경 변수 GEMINI_API_KEY가 설정되지 않았습니다. GitHub Actions의 Secret(GKEY) 및 env: 매핑을 확인하세요." >&2
fi


# 2.1. 데이터 파싱 (차트용 데이터: 변화 값 - 시간 순서대로)
JS_VALUES=$(awk -F ' : ' '
    { 
        gsub(/,/, "", $2); 
        values[NR] = $2 + 0;
    }
    END {
        change_values[1] = 0;
        
        for (i = 2; i <= NR; i++) {
            change_values[i] = values[i] - values[i-1];
        }

        for (j = 1; j <= NR; j++) {
            printf "%s", change_values[j]
            if (j < NR) {
                printf ", "
            }
        }
    }
' result.txt) 

# 2.2. JS_LABELS: 시간 레이블을 "월-일 시" 형식 (MM-DD HH시)으로 포맷합니다.
JS_LABELS=$(awk -F ' : ' '
    { 
        formatted_label = substr($1, 6, 5) " " substr($1, 12, 2) "시";
        labels[i++] = "\"" formatted_label "\""
    }
    END {
        for (j=0; j<i; j++) {
            printf "%s", labels[j]
            if (j < i-1) {
                printf ", "
            }
        }
    }
' result.txt) 

# 2.3. 메인 HTML 테이블 ROW 데이터 생성 (JS 페이지네이션을 위해 <tr> 태그만 생성)
RAW_TABLE_ROWS=$(awk -F ' : ' '
    function comma_format(n) {
        if (n == 0) return "0";
        s = int(n);
        if (s > 0) {
            sign = "+";
        } else if (s < 0) {
            sign = "-";
            s = -s;    
        } else {
            sign = "";
        }
        abs_s = (s < 0) ? -s : s;
        abs_s_str = abs_s ""; 
        result = "";
        while (abs_s_str ~ /[0-9]{4}/) {
            result = "," substr(abs_s_str, length(abs_s_str)-2) result;
            abs_s_str = substr(abs_s_str, 1, length(abs_s_str)-3);
        }
        return sign abs_s_str result;
    } 

    {
        formatted_time = substr($1, 6, 5) " " substr($1, 12, 2) "시";
        
        times[NR] = formatted_time; 
        values_str[NR] = $2;
        gsub(/,/, "", $2); 
        values_num[NR] = $2 + 0; 
    }
    END {
        for (i = NR; i >= 1; i--) {
            time_str = times[i];
            current_val_str = values_str[i]; 
            current_val_num = values_num[i]; 

            if (i > 1) {
                prev_val_num = values_num[i - 1];
                diff = current_val_num - prev_val_num;
                diff_display = comma_format(diff); 

                if (diff > 0) {
                    color_style = "color: #dc3545; font-weight: 600;";
                } else if (diff < 0) {
                    color_style = "color: #007bff; font-weight: 600;";
                } else {
                    diff_display = "0";
                    color_style = "color: #333; font-weight: 600;";
                }
            } else {
                diff_display = "---";
                color_style = "color: #6c757d;";
            } 

            printf "<tr>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; font-weight: bold; color: #333; background-color: white;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; text-align: right; background-color: white; %s\">%s</td>\
            </tr>\n", time_str, current_val_str, color_style, diff_display
        }
    }
' result.txt) 

# 2.4. 일별 집계 테이블 생성 (AWK)
DAILY_SUMMARY_TABLE=$(awk -F ' : ' '
    function comma_format_sum_only(n) {
        if (n == 0) return "0";
        s = int(n);
        if (s < 0) { s = -s; }
        s = s ""; 
        result = "";
        while (s ~ /[0-9]{4}/) {
            result = "," substr(s, length(s)-2) result;
            s = substr(s, 1, length(s)-3);
        }
        return (int(n) < 0 ? "-" : "") s result;
    }
    
    function comma_format_diff_only(n) {
        if (n == 0) return "0";
        s = int(n);
        if (s > 0) { sign = "+"; } 
        else if (s < 0) { sign = "-"; s = -s; } 
        else { return "0"; }
        s = s ""; 
        result = "";
        while (s ~ /[0-9]{4}/) {
            result = "," substr(s, length(s)-2) result;
            s = substr(s, 1, length(s)-3);
        }
        return sign s result;
    } 

    {
        numeric_value = $2;
        gsub(/,/, "", numeric_value);
        date = substr($1, 1, 10);
        last_value[date] = numeric_value; 
        if (!(date in added_dates)) {
            dates_arr[num_dates++] = date;
            added_dates[date] = 1;
        }
    }
    END {
        for (i = 0; i < num_dates; i++) {
            for (j = i + 1; j < num_dates; j++) {
                if (dates_arr[i] > dates_arr[j]) {
                    temp = dates_arr[i];
                    dates_arr[i] = dates_arr[j];
                    dates_arr[j] = temp;
                }
            }
        } 

        print "<table style=\"width: 100%; max-width: 1000px; border-collapse: separate; border-spacing: 0; border: 1px solid #ddd; font-size: 14px; min-width: 300px; border-radius: 8px; overflow: hidden; margin-top: 20px;\">";
        print "<thead><tr>\
            <th style=\"padding: 14px; background-color: white; border-right: 1px solid #ccc; text-align: left; color: #333;\">날짜</th>\
            <th style=\"padding: 14px; background-color: white; border-right: 1px solid #ccc; text-align: right; color: #333;\">값</th>\
            <th style=\"padding: 14px; background-color: white; text-align: right; color: #333;\">변화</th>\
        </tr></thead>";
        print "<tbody>"; 

        prev_value = 0;
        
        for (i = 0; i < num_dates; i++) {
            date = dates_arr[i];
            current_value = last_value[date]; 

            diff = current_value - prev_value;
            current_value_display = comma_format_sum_only(current_value);
            
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
            
            row_data[i] = sprintf("<tr>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white; color: #343a40;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; background-color: white; font-weight: bold; color: #333;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; text-align: right; background-color: white; %s\">%s</td>\
            </tr>", date, current_value_display, color_style, diff_display); 

            prev_value = current_value;
        } 

        for (i = num_dates - 1; i >= 0; i--) {
            print row_data[i];
        } 

        print "</tbody></table>";
    }
' result.txt) 

# 2.5. 일별 집계 차트용 값 파싱 (JS_DAILY_VALUES - 변경 없음)
JS_DAILY_VALUES=$(awk -F ' : ' '
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
        for (i = 0; i < num_dates; i++) {
            for (j = i + 1; j < num_dates; j++) {
                if (dates_arr[i] > dates_arr[j]) {
                    temp = dates_arr[i];
                    dates_arr[i] = dates_arr[j];
                    dates_arr[j] = temp;
                }
            }
        }
        
        for (i = 0; i < num_dates; i++) {
            printf "%s", last_value[dates_arr[i]]
            if (i < num_dates - 1) {
                printf ", "
            }
        }
    }
' result.txt) 

# 2.6. 일별 집계 차트용 레이블 파싱 (JS_DAILY_LABELS - 변경 없음)
JS_DAILY_LABELS=$(awk -F ' : ' '
    {
        date = substr($1, 1, 10);
        if (!(date in added_dates)) {
            dates_arr[num_dates++] = date;
            added_dates[date] = 1;
        }
    }
    END {
        for (i = 0; i < num_dates; i++) {
            for (j = i + 1; j < num_dates; j++) {
                if (dates_arr[i] > dates_arr[j]) {
                    temp = dates_arr[i];
                    dates_arr[i] = dates_arr[j];
                    dates_arr[j] = temp;
                }
            }
        }
        
        for (i = 0; i < num_dates; i++) {
            printf "\"%s\"", dates_arr[i]
            if (i < num_dates - 1) {
                printf ", "
            }
        }
    }
' result.txt) 

# 2.7. AI 예측용 원본 데이터 문자열 (프롬프트에 삽입)
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


# 2.8. AI 예측 로직 (API 호출 및 결과 처리)

MODEL="gemini-2.5-flash"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI_API_KEY}"

# 다음 날짜 계산
LAST_DATA_DATE=$(tail -n 1 result.txt | awk -F ' : ' '{print $1}' | cut -d ' ' -f 1)
TARGET_DATE=$(date -d "$LAST_DATA_DATE + 1 day" +%Y-%m-%d)

# 현재 월의 마지막 날짜 (월말) 계산
YEAR_MONTH=$(date -d "$LAST_DATA_DATE" +%Y-%m)
END_OF_MONTH_DATE=$(date -d "$YEAR_MONTH-01 + 1 month - 1 day" +%Y-%m-%d)

# JSON 페이로드에 들어갈 내용을 이스케이프하는 함수
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;s/\n/\\n/g;ta'
}


SYSTEM_PROMPT="**핵심 고려 사항: ${CONTEXTUAL_PRIORITY}**\n**데이터 맥락: 분석하는 데이터는 10월 28일에 오픈한 모바일 게임의 누적 매출 데이터입니다. (단위: 달러)**\n\n당신은 전문 데이터 분석가입니다. 제공된 시계열 누적 데이터를 분석하고, 다음 세 가지 핵심 정보를 포함하여 **최대 3문장 이내**로 응답하세요: 1) **현재 일별 변화 추이(상승, 하락, 횡보)**, 2) **다음 날(${TARGET_DATE})의 예상 최종 누적 값**, 3) **이달 말(${END_OF_MONTH_DATE})의 예상 최종 누적 값**. 불필요한 서론/결론, 목록, 표는 절대 포함하지 마세요. 추정치임을 명시해야 합니다."
USER_QUERY="다음은 시계열 누적 데이터입니다. 이 데이터를 분석하여 **${TARGET_DATE}**와 **${END_OF_MONTH_DATE}**의 예상 누적 값을 예측해주세요.\\n\\n데이터:\\n${RAW_DATA_PROMPT_CONTENT}"

JSON_SYSTEM_PROMPT=$(escape_json "$SYSTEM_PROMPT")
JSON_USER_QUERY=$(escape_json "$USER_QUERY")

PAYLOAD='{
    "contents": [{ "parts": [{ "text": "'"$JSON_USER_QUERY"'" }] }],
    "systemInstruction": { "parts": [{ "text": "'"$JSON_SYSTEM_PROMPT"'" }] },
    "tools": [{ "google_search": {} }]
}'

PREDICTION_HEADER_EMBED="AI 기반 추이 분석 및 예측: ${TARGET_DATE} 및 ${END_OF_MONTH_DATE}"
PREDICTION_TEXT_EMBED='<div class="error-message"><span style="font-weight: 700;">⚠️ 오류: API 키 없음.</span> 환경 변수 GEMINI_API_KEY가 설정되지 않아 예측을 실행할 수 없습니다. GitHub Actions의 Secret(GKEY) 설정 및 워크플로우 변수 매핑을 확인해주세요.</div>' 

if [ -n "$GEMINI_API_KEY" ]; then
    API_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -H "Accept: application/json" "$API_URL" -d "$PAYLOAD" 2>/dev/null)
    CURL_STATUS=$?

    if [ $CURL_STATUS -ne 0 ]; then
        PREDICTION_TEXT_EMBED="<div class=\"error-message\"><span style=\"font-weight: 700;\">❌ API 호출 실패.</span> Curl 상태 코드: $CURL_STATUS. 네트워크 연결 또는 API 서버 상태를 확인하세요.</div>"
        PREDICTION_HEADER_EMBED="AI 기반 추이 분석 및 예측 (Curl 오류)"
    elif echo "$API_RESPONSE" | grep -q '"error":'; then
        ERROR_MESSAGE=$(echo "$API_RESPONSE" | grep -o '"message": "[^"]*"' | head -n 1 | sed 's/"message": "//; s/"$//')
        PREDICTION_TEXT_EMBED="<div class=\"error-message\"><span style=\"font-weight: 700;\">⚠️ 예측 결과 실패.</span> API 오류: ${ERROR_MESSAGE}</div>"
        PREDICTION_HEADER_EMBED="AI 기반 추이 분석 및 예측 (API 오류)"
    else
        RAW_TEXT_CONTENT=$(echo "$API_RESPONSE" | jq -r '.candidates[0].content.parts[0].text // ""' 2>/dev/null)

        if [ -z "$RAW_TEXT_CONTENT" ]; then
            BLOCK_REASON=$(echo "$API_RESPONSE" | jq -r '.candidates[0].finishReason // .promptFeedback.blockReason // ""' 2>/dev/null)
            
            if [ -n "$BLOCK_REASON" ]; then
                 PREDICTION_TEXT_EMBED="<div class=\"error-message\"><span style=\"font-weight: 700;\">⚠️ 응답 필터링됨.</span> 응답 내용이 정책에 의해 차단되었거나 (Finish Reason: ${BLOCK_REASON}) 누락되었습니다.</div>"
                 PREDICTION_HEADER_EMBED="AI 기반 추이 분석 및 예측 (차단 오류)"
            else
                 PREDICTION_TEXT_EMBED="<div class=\"error-message\"><span style=\"font-weight: 700;\">⚠️ 응답 파싱 실패.</span> 예측 텍스트를 파싱할 수 없습니다. 이는 API 응답 구조가 예상과 다르거나, \`jq\` 명령어를 찾을 수 없을 때 발생합니다.</div>"
                 PREDICTION_HEADER_EMBED="AI 기반 추이 분석 및 예측 (파싱 오류)"
            fi
        else
            FORMATTED_TEXT=$(echo "$RAW_TEXT_CONTENT" | sed ':a;N;$!ba;s/\n/<br>/g' | sed 's/\t/&nbsp;&nbsp;&nbsp;&nbsp;/g')

            SOURCES_HTML=""
            SOURCES_ARRAY=$(echo "$API_RESPONSE" | jq -r '.candidates[0].groundingMetadata.groundingAttributions[] | select(.web) | [.web.uri, .web.title] | @tsv' 2>/dev/null)
            
            if [ -n "$SOURCES_ARRAY" ]; then
                FIRST_SOURCE=$(echo "$SOURCES_ARRAY" | head -n 1)
                URI=$(echo "$FIRST_SOURCE" | awk '{print $1}')
                TITLE=$(echo "$FIRST_SOURCE" | awk '{$1=""; print $0}' | xargs)

                if [ ! -z "$URI" ] && [ ! -z "$TITLE" ]; then
                    SOURCES_HTML="<div class=\"sources-container\">
                        <p style=\"font-size: 12px; color: #555; margin-bottom: 5px;\">출처 (Google Search):</p>
                        <p style=\"font-size: 12px; margin: 2px 0;\"><a href=\"${URI}\" target=\"_blank\" style=\"color: #007bff; text-decoration: none;\">${TITLE}</a></p>
                    </div>"
                fi
            fi
            
            PREDICTION_TEXT_EMBED="<div class=\"success-message\">${FORMATTED_TEXT}${SOURCES_HTML}</div>"
        fi
    fi
fi


# 2.9. HTML 파일 생성 (money.html)
# 레이아웃과 내용 표시 문제를 해결한 최종 HTML 구조입니다.
cat << CHART_END > money.html
<!DOCTYPE html>
<html>
<head>
    <title>데이터 변화 추이 대시보드</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js"></script>
    <style>
        /* 좌우 꽉 참 및 내용 대비 문제 해결 CSS */
        body { font-family: 'Inter', sans-serif; margin: 0; padding: 0; background-color: #f7f7f7; color: #333; }
        
        .container { 
            width: 100%; /* 좌우 꽉 채우기 */
            max-width: 1400px; 
            margin: 0 auto; 
            padding: 10px; /* 내부 여백 최소화 */
            background: white; 
            border-radius: 0; 
            box-shadow: none; 
        }
        
        h1 { text-align: center; color: #333; margin-bottom: 5px; font-size: 26px; font-weight: 700; }
        p.update-time { text-align: center; color: #777; margin-bottom: 20px; font-size: 14px; }
        
        .chart-container { 
            margin-bottom: 30px; 
            border: 1px solid #eee; 
            border-radius: 8px; 
            padding: 15px; 
            background: #fff; 
            height: 40vh; 
            min-height: 300px; 
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.05);
            position: relative; /* 메시지 배치를 위해 추가 */
        }
        
        h2 { 
            margin-top: 30px; 
            margin-bottom: 10px; 
            text-align: center; 
            color: #343a40; 
            font-size: 22px; 
            font-weight: 600;
            border-bottom: 2px solid #343a40; 
            padding-bottom: 8px; 
            display: inline-block;
            width: auto;
            margin-left: auto;
            margin-right: auto;
        }
        
        #daily-chart-header {
            margin-top: 40px !important; 
        }
        
        /* AI 예측 섹션 스타일 */
        .prediction-section {
            padding: 20px;
            margin-bottom: 30px; 
            background-color: #f0f8ff; 
            border: 2px solid #007bff;
            border-radius: 12px;
            text-align: center;
        }
        .prediction-section h2 {
            color: #0056b3;
            margin-top: 0;
            border-bottom: none;
            padding-bottom: 0;
            font-size: 24px;
        }
        
        /* 오류 메시지 스타일: 대비 강화 */
        .error-message {
            text-align: left;
            padding: 15px;
            background-color: #ffe0e6; /* 밝은 배경 */
            border: 1px solid #dc3545; 
            color: #dc3545; /* 빨간 텍스트 */
            border-radius: 8px;
            line-height: 1.6;
            font-size: 15px;
            margin-top: 20px;
        }
        
        /* 성공 메시지 컨테이너 */
        .success-message {
            text-align: left;
            padding: 15px;
            background-color: white;
            border: 1px solid #ccc;
            border-radius: 8px;
            min-height: 50px;
            font-size: 15px;
            line-height: 1.6;
            margin-top: 20px;
            color: #333; /* 검은 텍스트 */
        }
        
        .sources-container {
             margin-top: 20px; 
             border-top: 1px solid #eee; 
             padding-top: 10px;
        }
        
        /* 데이터 없음 메시지 스타일 */
        .no-data-message {
             position: absolute; /* 차트 중앙에 배치 */
             top: 50%;
             left: 50%;
             transform: translate(-50%, -50%);
             text-align: center; 
             color: #6c757d; 
             padding: 20px; 
             font-size: 16px;
             font-weight: 600;
             width: 80%; /* 중앙 정렬을 위해 너비 지정 */
        }

        /* --- 페이지네이션 및 테이블 스타일 --- (나머지는 동일) */
        .pagination-controls {
            display: flex;
            justify-content: center;
            align-items: center;
            margin-top: 15px;
            margin-bottom: 40px;
            gap: 10px;
        }
        .pagination-button {
            background-color: #007bff;
            color: white;
            border: none;
            padding: 8px 15px;
            border-radius: 6px;
            cursor: pointer;
            transition: background-color 0.2s, opacity 0.2s;
            font-weight: 600;
        }
        .pagination-button:hover:not(:disabled) {
            background-color: #0056b3;
        }
        .pagination-button:disabled {
            background-color: #ccc;
            cursor: not-allowed;
            opacity: 0.6;
        }
        .page-info {
            font-weight: 600;
            color: #555;
            font-size: 15px;
        }
        .data-table-wrapper {
            width: 100%; 
            max-width: 1000px; 
            margin: 0 auto; 
            border-collapse: separate; 
            border-spacing: 0; 
            border: 1px solid #ddd; 
            font-size: 14px; 
            min-width: 300px; 
            border-radius: 8px; 
            overflow: hidden;
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- <h1>데이터 변화 추이 대시보드</h1> 제목 제거됨 -->
        <p class="update-time">최근 업데이트 시간: $(tail -n 1 result.txt | awk -F ' : ' '{print $1}')</p>
        
        <div class="prediction-section">
            <h2 id="prediction-header">${PREDICTION_HEADER_EMBED}</h2>
            <div id="predictionResult">
                ${PREDICTION_TEXT_EMBED}
            </div>
        </div>
        
        <div style="text-align: center;">
            <h2 id="daily-chart-header">일일 집계 추이</h2>
        </div>
        <div class="chart-container">
            <canvas id="dailyChart"></canvas>
            <p id="dailyChartNoData" class="no-data-message" style="display: none;">일일 집계 데이터가 없어 차트를 그릴 수 없습니다.</p>
        </div>
        
        <div style="text-align: center;">
            <h2>일일 집계 기록 (최신순)</h2>
        </div>
        <div>
            ${DAILY_SUMMARY_TABLE}
        </div> 
        
        <div style="text-align: center;">
            <h2>기록 시간별 변화 값 추이</h2>
        </div>
        <div class="chart-container">
            <canvas id="simpleChart"></canvas>
            <p id="simpleChartNoData" class="no-data-message" style="display: none;">데이터가 없어 차트를 그릴 수 없습니다.</p>
        </div> 

        
        <div style="text-align: center;">
            <h2>데이터 기록 (최신순)</h2>
        </div>
        
        <div id="dataRecordsContainer">
            </div>
        <div id="paginationControls" class="pagination-controls">
            </div>
        
    </div>
    
    <script>
    // 🚨 셸 스크립트에서 파싱된 동적 데이터가 여기에 삽입됩니다.
    
    // 1. 차트 데이터
    const chartData = [${JS_VALUES}];
    const chartLabels = [${JS_LABELS}]; 

    // 2. 일별 최종 값 데이터
    const jsDailyValues = [${JS_DAILY_VALUES}];
    const jsDailyLabels = [${JS_DAILY_LABELS}]; 

    // 3. 페이지네이션을 위한 전체 ROW 데이터 (AWK에서 최신순으로 생성)
    // 줄바꿈 문자로 분리하여 <tr> 태그 문자열 배열로 만듭니다.
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
        
        // 테이블 구조 생성
        const tableHtml = \`
            <div class="data-table-wrapper">
            <table style="width: 100%; border-collapse: separate; border-spacing: 0;">
                <thead>
                    <tr>
                        <th style="padding: 14px; background-color: white; border-right: 1px solid #ccc; text-align: left; color: #333;">시간</th>
                        <th style="padding: 14px; background-color: white; border-right: 1px solid #ccc; text-align: right; color: #333;">값</th>
                        <th style="padding: 14px; background-color: white; text-align: right; color: #333;">변화</th>
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
            // 테이블 영역으로 스크롤 이동
            document.getElementById('dataRecordsContainer').scrollIntoView({ behavior: 'smooth' });
        }
    };
    
    // 초기 렌더링
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
            // 정수형으로 포맷팅
            formattedValue = new Intl.NumberFormat('ko-KR', { maximumFractionDigits: 0 }).format(value);
        }
        return formattedValue;
    };
    
    const formatTooltip = function(context) {
        let label = context.dataset.label || '';
        if (label) {
            label += ': ';
        }
        if (context.parsed.y !== null) {
            // 변화값은 부호를 포함하여 포맷팅
            const isChangeValue = context.chart.options.plugins.title.text.includes('변화 값');
            label += new Intl.NumberFormat('ko-KR', { signDisplay: isChangeValue ? 'always' : 'auto', maximumFractionDigits: 0 }).format(context.parsed.y);
        }
        return label;
    };


    // ---------------------------------------------
    // 1. 차트 렌더링 로직 (simpleChart - 빨간색)
    // --------------------------------------------- 

    const simpleChartCanvas = document.getElementById('simpleChart');
    if (chartData.length === 0) {
        // 차트 캔버스를 숨기고 데이터 없음 메시지를 표시합니다.
        simpleChartCanvas.style.display = 'none';
        document.getElementById('simpleChartNoData').style.display = 'block';
    } else {
        document.getElementById('simpleChartNoData').style.display = 'none';
        new Chart(simpleChartCanvas.getContext('2d'), {
            type: 'line', 
            data: {
                labels: chartLabels,
                datasets: [{
                    label: '변화 값', 
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
                        title: { display: true, text: '시간 (MM-DD HH시)', font: { size: 14, weight: 'bold' } }, 
                        ticks: {
                            maxRotation: 45, 
                            minRotation: 45,
                            autoSkip: true,
                            maxTicksLimit: 15, 
                            font: { size: 12 }
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
                    legend: { display: false },
                    tooltip: {
                        mode: 'index',
                        intersect: false,
                        bodyFont: { size: 14 },
                        callbacks: { label: formatTooltip }
                    },
                    title: {
                        display: true,
                        text: '시간별 변화 값 추이 (MM-DD HH시)', 
                        font: { size: 18, weight: 'bold' },
                        padding: { top: 10, bottom: 10 }
                    }
                }
            }
        });
    } 

    // ---------------------------------------------
    // 2. 차트 렌더링 로직 (dailyChart - 파란색 - 변경 없음)
    // ---------------------------------------------
    const dailyChartCanvas = document.getElementById('dailyChart');
    
    if (jsDailyValues.length === 0) {
        // 차트 캔버스를 숨기고 데이터 없음 메시지를 표시합니다.
        dailyChartCanvas.style.display = 'none';
        document.getElementById('dailyChartNoData').style.display = 'block';
    } else {
        document.getElementById('dailyChartNoData').style.display = 'none';
        new Chart(dailyChartCanvas.getContext('2d'), {
            type: 'line',
            data: {
                labels: jsDailyLabels,
                datasets: [{
                    label: '일일 최종 값',
                    data: jsDailyValues,
                    borderColor: 'rgba(0, 123, 255, 1)',
                    backgroundColor: 'rgba(0, 123, 255, 0.2)', 
                    borderWidth: 4, 
                    tension: 0.3, 
                    pointRadius: 6,
                    pointBackgroundColor: 'rgba(0, 123, 255, 1)', 
                    pointHoverRadius: 8,
                    fill: 'start' 
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: {
                        type: 'category', 
                        title: { display: true, text: '날짜', font: { size: 14, weight: 'bold' } },
                        ticks: { 
                            font: { size: 12 },
                            maxRotation: 45, 
                            minRotation: 45 
                        }
                    },
                    y: {
                        title: { display: true, text: '최종 값', font: { size: 14, weight: 'bold' } },
                        beginAtZero: false,
                        grid: { color: 'rgba(0, 0, 0, 0.05)' },
                        ticks: { callback: formatYAxisTick }
                    }
                },
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        mode: 'index',
                        intersect: false,
                        bodyFont: { size: 14 },
                        callbacks: { label: formatTooltip }
                    },
                    title: {
                        display: true,
                        text: '일별 최종 값 변화 추이 (YYYY-MM-DD)',
                        font: { size: 18, weight: 'bold' },
                        padding: { top: 10, bottom: 10 }
                    }
                }
            }
        });
    }
    </script>
</body>
</html>
CHART_END

