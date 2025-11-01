#!/bin/bash
#


# 1. 데이터 파싱 (차트용 데이터: 시간 순서대로)

# JS_VALUES: 쉼표로 구분된 값 (차트 데이터용)
# NOTE: 차트 생성을 위해 쉼표(,)를 제거한 숫자형 배열로 변환
JS_VALUES=$(awk -F ' : ' '
    { 
        # 값에서 쉼표(,) 제거
        gsub(/,/, "", $2); 
        values[i++] = $2
    }
    END {
        # 배열의 요소를 ", "로 연결하여 출력
        for (j=0; j<i; j++) {
            printf "%s", values[j]
            if (j < i-1) {
                printf ", "
            }
        }
    }
' result.txt)

# JS_LABELS: 따옴표로 감싸고 쉼표로 구분된 시간 (차트 레이블용)
# NOTE: 시간 문자열에서 HH:MM 부분만 추출
JS_LABELS=$(awk -F ' : ' '
    { 
        # HH:MM 부분만 추출 (예: "23:29")
        match($1, /[0-9]{2}:[0-9]{2}/, short_label_arr);
        short_label = short_label_arr[0];
        labels[i++] = "\"" short_label "\""
    }
    END {
        # 배열의 요소를 ", "로 연결하여 출력
        for (j=0; j<i; j++) {
            printf "%s", labels[j]
            if (j < i-1) {
                printf ", "
            }
        }
    }
' result.txt)

# 2. 메인 HTML 테이블 생성 (차이값 계산 및 역순 정렬 로직 포함)
HTML_TABLE_ROWS=$(awk -F ' : ' '
    # 🚨 Awk 함수: 숫자를 천 단위 구분 기호로 포맷팅하고 부호를 붙임
    function comma_format(n) {
        # n이 0이면 "0" 반환
        if (n == 0) return "0";
        
        s = int(n);
        
        # 부호 결정
        if (s > 0) {
            sign = "+";
        } else if (s < 0) {
            sign = "-"; # 음수일 때 마이너스 부호 명시
            s = -s;     # 절대값 사용
        } else {
            sign = "";
        }
        
        s = s "";  # 절대값 숫자를 문자열로 변환
        
        result = "";
        while (s ~ /[0-9]{4}/) {
            # 오른쪽에서 세 자리마다 쉼표 삽입
            result = "," substr(s, length(s)-2) result;
            s = substr(s, 1, length(s)-3);
        }
        
        return sign s result; # 최종 결과에 부호 추가
    }

    # 초기화 및 데이터 저장
    {
        # $1: 시간 문자열, $2: 값 문자열 (쉼표 포함)
        times[NR] = $1;
        values_str[NR] = $2;
        
        # 값에서 쉼표(,) 제거 후 숫자형으로 저장
        gsub(/,/, "", $2); 
        values_num[NR] = $2 + 0; 
    }
    END {
        # 테이블 스타일 및 헤더 정의 (외곽 테두리: #ddd, 내부: #ccc / #eee 유지)
        print "<table style=\"width: 100%; max-width: 1000px; border-collapse: separate; border-spacing: 0; border: 1px solid #ddd; font-size: 14px; min-width: 300px; border-radius: 8px; overflow: hidden;\">";
        print "<thead><tr>\
            <th style=\"padding: 14px; background-color: white; border-right: 1px solid #ccc; text-align: left; color: #333;\">시간</th>\
            <th style=\"padding: 14px; background-color: white; border-right: 1px solid #ccc; text-align: right; color: #333;\">값</th>\
            <th style=\"padding: 14px; background-color: white; text-align: right; color: #333;\">변화</th>\
        </tr></thead>";
        print "<tbody>";

        # 역순으로 순회 (최신 데이터부터 출력)
        for (i = NR; i >= 1; i--) {
            time_str = times[i];
            current_val_str = values_str[i]; 
            current_val_num = values_num[i];

            if (i > 1) {
                prev_val_num = values_num[i - 1];
                diff = current_val_num - prev_val_num;
                diff_display = comma_format(diff);

                # 🚨 색상: + (붉은색), - (파란색), 0 (검은색)
                if (diff > 0) {
                    color_style = "color: #dc3545; font-weight: 600;"; /* Red: 상승 */
                } else if (diff < 0) {
                    color_style = "color: #007bff; font-weight: 600;"; /* Blue: 하락 */
                } else {
                    diff_display = "0";
                    color_style = "color: #333; font-weight: 600;"; /* Black: 변화 없음 */
                }
            } else {
                diff_display = "---";
                color_style = "color: #6c757d;";
            }

            # HTML 행 출력 (내부 구분선: #eee 유지)
            printf "<tr>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; font-weight: bold; color: #333; background-color: white;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; text-align: right; background-color: white; %s\">%s</td>\
            </tr>\n", time_str, current_val_str, color_style, diff_display
        }
        
        print "</tbody></table>";
    }
' result.txt)

# 3. 일별 집계 테이블 생성 (테이블 라인 색상 통일)
DAILY_SUMMARY_TABLE=$(awk -F ' : ' '
    # 총합 값에만 사용되는 포맷 함수 (부호 없음)
    function comma_format_sum_only(n) {
        if (n == 0) return "0";
        
        s = int(n);
        
        if (s < 0) {
            s = -s;
        }
        
        s = s ""; 
        
        result = "";
        while (s ~ /[0-9]{4}/) {
            result = "," substr(s, length(s)-2) result;
            s = substr(s, 1, length(s)-3);
        }
        
        return (int(n) < 0 ? "-" : "") s result;
    }
    
    # 변화 값에만 사용되는 포맷 함수 (부호 필수)
    function comma_format_diff_only(n) {
        if (n == 0) return "0";
        
        s = int(n);
        
        if (s > 0) {
            sign = "+";
        } else if (s < 0) {
            sign = "-"; 
            s = -s;     
        } else {
            return "0";
        }
        
        s = s ""; 
        
        result = "";
        while (s ~ /[0-9]{4}/) {
            result = "," substr(s, length(s)-2) result;
            s = substr(s, 1, length(s)-3);
        }
        
        return sign s result;
    }


    # Initial data collection
    {
        # 1. 값에서 쉼표(,) 제거 후 숫자형으로 변환
        numeric_value = $2;
        gsub(/,/, "", numeric_value);
        
        # 2. 날짜 추출 (YYYY-MM-DD)
        date = substr($1, 1, 10);
        
        # 3. 마지막으로 기록된 값을 저장
        last_value[date] = numeric_value; 
        
        # 고유 날짜 배열 및 카운트
        if (!(date in added_dates)) {
            dates_arr[num_dates++] = date;
            added_dates[date] = 1;
        }
    }
    END {
        # Simple Bubble Sort for YYYY-MM-DD strings (Chronological order: Oldest -> Newest)
        for (i = 0; i < num_dates; i++) {
            for (j = i + 1; j < num_dates; j++) {
                if (dates_arr[i] > dates_arr[j]) {
                    temp = dates_arr[i];
                    dates_arr[i] = dates_arr[j];
                    dates_arr[j] = temp;
                }
            }
        }

        # 🚨 테이블 시작 (외곽 테두리: #ddd로 통일)
        print "<table style=\"width: 100%; max-width: 1000px; border-collapse: separate; border-spacing: 0; border: 1px solid #ddd; font-size: 14px; min-width: 300px; border-radius: 8px; overflow: hidden; margin-top: 20px;\">";
        # 테이블 헤더 (내부 구분선: #ccc 유지)
        print "<thead><tr>\
            <th style=\"padding: 14px; background-color: white; border-right: 1px solid #ccc; text-align: left; color: #333;\">날짜</th>\
            <th style=\"padding: 14px; background-color: white; border-right: 1px solid #ccc; text-align: right; color: #333;\">값</th>\
            <th style=\"padding: 14px; background-color: white; text-align: right; color: #333;\">변화</th>\
        </tr></thead>";
        print "<tbody>";


        # 1. 정렬된 날짜를 순회하며 전날 데이터와 비교 및 row_data 배열에 저장 (순차적)
        prev_value = 0;
        
        for (i = 0; i < num_dates; i++) {
            date = dates_arr[i];
            current_value = last_value[date]; # 마지막 값 사용

            # 변화값 계산
            diff = current_value - prev_value;
            
            # 마지막 값 포맷팅
            current_value_display = comma_format_sum_only(current_value);
            
            # 변화값 포맷팅 및 색상 설정 (빨강/파랑/회색)
            if (i == 0) {
                # 첫날은 비교값 없음
                diff_display = "---";
                color_style = "color: #6c757d;"; /* Gray */
            } else {
                diff_display = comma_format_diff_only(diff);
                if (diff > 0) {
                    color_style = "color: #dc3545; font-weight: 600;"; /* Red: 증가 */
                } else if (diff < 0) {
                    color_style = "color: #007bff; font-weight: 600;"; /* Blue: 감소 */
                } else {
                    diff_display = "0";
                    color_style = "color: #333; font-weight: 600;"; /* Black: 변화 없음 */
                }
            }
            
            # 🚨 HTML 행 내용을 저장. (내부 구분선: #eee 유지)
            row_data[i] = sprintf("<tr>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white; color: #343a40;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; background-color: white; font-weight: bold; color: #333;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; text-align: right; background-color: white; %s\">%s</td>\
            </tr>", date, current_value_display, color_style, diff_display);

            # 다음 반복을 위해 현재 값을 이전 값으로 저장
            prev_value = current_value;
        }

        # 2. 🚨 역순으로 순회하며 테이블 행 출력 (최신 날짜가 상단에 오도록)
        for (i = num_dates - 1; i >= 0; i--) {
            print row_data[i];
        }

        print "</tbody></table>";
    }
' result.txt)

# 3-1. 일별 집계 차트용 값 파싱 (JS_DAILY_VALUES)
# NOTE: 각 날짜의 마지막 값을 추출하여 시간 순서대로 정렬 (YYYY-MM-DD)
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
        # Sort chronologically (Oldest -> Newest)
        for (i = 0; i < num_dates; i++) {
            for (j = i + 1; j < num_dates; j++) {
                if (dates_arr[i] > dates_arr[j]) {
                    temp = dates_arr[i];
                    dates_arr[i] = dates_arr[j];
                    dates_arr[j] = temp;
                }
            }
        }
        
        # Collect values in chronological order
        for (i = 0; i < num_dates; i++) {
            printf "%s", last_value[dates_arr[i]]
            if (i < num_dates - 1) {
                printf ", "
            }
        }
    }
' result.txt)

# 3-2. 일별 집계 차트용 레이블 파싱 (JS_DAILY_LABELS)
# NOTE: 정렬된 날짜를 따옴표로 감싸서 추출
JS_DAILY_LABELS=$(awk -F ' : ' '
    {
        date = substr($1, 1, 10);
        if (!(date in added_dates)) {
            dates_arr[num_dates++] = date;
            added_dates[date] = 1;
        }
    }
    END {
        # Sort chronologically (Oldest -> Newest)
        for (i = 0; i < num_dates; i++) {
            for (j = i + 1; j < num_dates; j++) {
                if (dates_arr[i] > dates_arr[j]) {
                    temp = dates_arr[i];
                    dates_arr[i] = dates_arr[j];
                    dates_arr[j] = temp;
                }
            }
        }
        
        # Collect labels in chronological order
        for (i = 0; i < num_dates; i++) {
            printf "\"%s\"", dates_arr[i]
            if (i < num_dates - 1) {
                printf ", "
            }
        }
    }
' result.txt)

# 4. AI 예측용 원본 데이터 문자열 (프롬프트에 삽입)
# RAW_DATA_PROMPT_CONTENT: 모든 줄바꿈을 \n으로 바꾸고 따옴표를 이스케이프하여 하나의 JS 문자열로 만듭니다.
RAW_DATA_PROMPT_CONTENT=$(awk '
    {
        # 따옴표 이스케이프
        gsub(/"/, "\\\"", $0);
        # 문자열을 빌드하고 줄바꿈을 \n으로 이스케이프
        output = output $0 "\\n";
    }
    END {
        # 마지막에 추가된 \n 제거
        sub(/\\n$/, "", output);
        print output;
    }
' result.txt)


# 5. HTML 파일 생성 (index.html)
cat << CHART_END > index.html
<!DOCTYPE html>
<html>
<head>
    <title>데이터 변화 추이 대시보드</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <!-- Chart.js CDN 링크 -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js"></script>
    <style>
        body { font-family: 'Inter', sans-serif; margin: 0; background-color: #f7f7f7; color: #333; }
        .container { width: 95%; max-width: 1000px; margin: 20px auto; padding: 20px; background: white; border-radius: 12px; box-shadow: 0 8px 16px rgba(0, 0, 0, 0.1); }
        h1 { text-align: center; color: #333; margin-bottom: 5px; font-size: 26px; font-weight: 700; }
        p.update-time { text-align: center; color: #777; margin-bottom: 30px; font-size: 14px; }
        /* 차트 컨테이너가 모바일에서 너무 작아지지 않도록 최소 높이 설정 */
        .chart-container { 
            margin-bottom: 50px; 
            border: 1px solid #eee; 
            border-radius: 8px; 
            padding: 15px; 
            background: #fff; 
            height: 40vh; 
            min-height: 300px; 
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.05);
        }
        /* 🚨 h2 스타일: 두 제목 모두 검정색으로 통일 */
        h2 { 
            margin-top: 40px; 
            margin-bottom: 15px; 
            text-align: center; 
            color: #343a40; /* 검정색 */
            font-size: 22px; 
            font-weight: 600;
            border-bottom: 2px solid #343a40; /* 검정색 */
            padding-bottom: 10px;
            display: inline-block;
            width: auto;
            margin-left: auto;
            margin-right: auto;
        }
        /* 일일 집계 차트 제목 마진 조정 */
        #daily-chart-header {
            margin-top: 60px !important; 
        }
        /* New styles for Prediction Section */
        .prediction-section {
            padding: 20px;
            margin-bottom: 40px;
            background-color: #e9f7ff;
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
        #predictButton {
            background-color: #007bff;
            color: white;
            padding: 12px 25px;
            border: none;
            border-radius: 8px;
            font-size: 18px;
            font-weight: 600;
            cursor: pointer;
            transition: background-color 0.3s, transform 0.1s;
            box-shadow: 0 4px 6px rgba(0, 123, 255, 0.3);
            margin-top: 15px;
        }
        #predictButton:hover:not(:disabled) {
            background-color: #0056b3;
            transform: translateY(-1px);
        }
        #predictButton:disabled {
            background-color: #a0c9f8;
            cursor: not-allowed;
        }
        #predictionResult {
            margin-top: 20px;
            padding: 15px;
            background-color: white;
            border: 1px solid #ccc;
            border-radius: 8px;
            text-align: left;
            white-space: pre-wrap;
            min-height: 50px;
            font-size: 15px;
            line-height: 1.6;
        }
        .loading-text {
            color: #007bff;
            font-weight: 600;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>데이터 변화 추이</h1>
        <p class="update-time">최근 업데이트 시간: $(tail -n 1 result.txt | awk -F ' : ' '{print $1}')</p>
        
        <!-- 🚨 1. AI 예측 섹션 추가 -->
        <div class="prediction-section">
            <h2>AI 기반 누적 값 예측</h2>
            <p>제공된 데이터를 기반으로 1개월(30일) 및 3개월(90일) 후의 최종 누적 값을 예측합니다.</p>
            <button id="predictButton" onclick="predictData()">
                1개월 & 3개월 누적 예측 시작
            </button>
            <div id="predictionResult">
                결과가 여기에 표시됩니다. 예측 버튼을 눌러주세요.
            </div>
        </div>
        
        <!-- 2. 일일 집계 차트 영역 -->
        <div style="text-align: center;">
            <h2 id="daily-chart-header">일일 집계 추이</h2>
        </div>
        <div class="chart-container">
            <canvas id="dailyChart"></canvas>
        </div>
        
        <!-- 3. 일일 집계 테이블 영역 (위치 유지) -->
        <div style="text-align: center;">
            <h2>일일 집계 기록 (최신순)</h2>
        </div>
        <div>
            ${DAILY_SUMMARY_TABLE}
        </div>

        <!-- 4. 데이터 기록 차트 영역 -->
        <div style="text-align: center;">
            <h2>기록 시간별 변화 추이</h2>
        </div>
        <div class="chart-container">
            <canvas id="simpleChart"></canvas>
        </div>

        
        <!-- 5. 데이터 기록 표 영역 -->
        <div style="text-align: center;">
            <h2>데이터 기록 (최신순)</h2>
        </div>
        <div>
            ${HTML_TABLE_ROWS}
        </div>
        
    </div>
    
    <script>
    // 🚨 셸 스크립트에서 파싱된 동적 데이터가 여기에 삽입됩니다.
    
    // AI 예측에 사용되는 원본 데이터 문자열 (프롬프트에 삽입)
    const RAW_DATA_STRING = "${RAW_DATA_PROMPT_CONTENT}";

    // 1. 시간별 상세 기록 데이터 (빨간색 차트)
    const chartData = [${JS_VALUES}];
    const chartLabels = [${JS_LABELS}];

    // 2. 일별 최종 값 데이터 (파란색 차트)
    const jsDailyValues = [${JS_DAILY_VALUES}];
    const jsDailyLabels = [${JS_DAILY_LABELS}];

    const formatYAxisTick = function(value) {
        if (value === 0) return '0';
        
        const absValue = Math.abs(value);
        let formattedValue;

        if (absValue >= 1000000000) {
            formattedValue = (value / 1000000000).toFixed(1).replace(/\.0$/, '') + 'B';
        } else if (absValue >= 1000000) {
            formattedValue = (value / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
        } else if (absValue >= 1000) {
            formattedValue = (value / 1000).toFixed(1).replace(/\.0$/, '') + 'K';
        } else {
            formattedValue = new Intl.NumberFormat('ko-KR').format(value);
        }
        return formattedValue;
    };
    
    const formatTooltip = function(context) {
        let label = context.dataset.label || '';
        if (label) {
            label += ': ';
        }
        if (context.parsed.y !== null) {
            label += new Intl.NumberFormat('ko-KR').format(context.parsed.y);
        }
        return label;
    };


    /**
     * Exponential backoff을 구현하여 API 호출을 재시도합니다.
     * @param {string} apiUrl - API URL
     * @param {object} options - Fetch 옵션
     * @param {number} maxRetries - 최대 재시도 횟수
     * @param {number} initialDelay - 초기 딜레이 (ms)
     * @returns {Promise<Response>} API 응답
     */
    async function fetchWithBackoff(apiUrl, options, maxRetries = 5, initialDelay = 1000) {
        let delay = initialDelay;
        for (let attempt = 0; attempt < maxRetries; attempt++) {
            try {
                const response = await fetch(apiUrl, options);
                // 403 Forbidden을 포함하여 실패 응답 코드를 여기서 확인
                if (response.status !== 429 && response.ok) {
                    return response;
                }
                
                // 429 Too Many Requests이거나 다른 일시적 오류인 경우 재시도
                if (attempt < maxRetries - 1) {
                    await new Promise(resolve => setTimeout(resolve, delay));
                    delay *= 2; // 지연 시간 두 배 증가
                } else {
                    // 마지막 시도 후에도 실패하면 에러를 발생시켜 catch 블록으로 전달
                    throw new Error(\`API request failed after \${maxRetries} attempts with status \${response.status}\`);
                }
            } catch (error) {
                // 네트워크 오류 등의 경우
                if (attempt < maxRetries - 1) {
                    await new Promise(resolve => setTimeout(resolve, delay));
                    delay *= 2;
                } else {
                    throw new Error(\`API request failed after \${maxRetries} attempts: \${error.message}\`);
                }
            }
        }
    }


    /**
     * Gemini API를 호출하여 데이터 누적 값을 예측합니다.
     */
    async function predictData() {
        const button = document.getElementById('predictButton');
        const resultDiv = document.getElementById('predictionResult');

        button.disabled = true;
        resultDiv.innerHTML = '<span class="loading-text">데이터를 분석하고 예측하는 중입니다... 잠시만 기다려주세요.</span>';
        
        const systemPrompt = "당신은 전문적인 데이터 분석가이자 예측 모델입니다. 제공된 시계열 누적 데이터를 분석하고, 과거 성장 추세(선형, 지수 등)를 파악하여 1개월(30일) 및 3개월(90일) 후의 최종 누적 값을 예측하세요. 응답은 분석 결과와 예측 값을 간결하고 명확한 한국어 문단으로 제공해야 하며, 예측 값은 추정치임을 명시하세요.";

        const userQuery = \`다음은 'YYYY-MM-DD HH:MM:SS : 값' 형식의 시계열 누적 데이터입니다. 이 데이터를 사용하여 1개월(30일) 후의 예상 누적 값과 3개월(90일) 후의 예상 누적 값을 예측해주세요.\\n\\n데이터:\\n\${RAW_DATA_STRING}\`;
        
        // API 설정
        const apiKey = "";
        const apiUrl = \`https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-09-2025:generateContent?key=\${apiKey}\`;

        // 🚨 디버깅을 위한 로그 추가
        console.log("------------------------------------------");
        console.log("API 호출을 시도합니다.");
        console.log("사용 모델:", "gemini-2.5-flash-preview-09-2025");
        console.log("요청 URL (키는 실행 환경에서 주입됨):", apiUrl);
        console.log("------------------------------------------");


        const payload = {
            contents: [{ parts: [{ text: userQuery }] }],
            systemInstruction: { parts: [{ text: systemPrompt }] },
            tools: [{ "google_search": {} }], 
        };

        try {
            const response = await fetchWithBackoff(apiUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });

            const result = await response.json();
            const candidate = result.candidates?.[0];

            if (candidate && candidate.content?.parts?.[0]?.text) {
                const text = candidate.content.parts[0].text;
                
                let sourcesHtml = '';
                const groundingMetadata = candidate.groundingMetadata;
                if (groundingMetadata && groundingMetadata.groundingAttributions) {
                    const sources = groundingMetadata.groundingAttributions
                        .map(attribution => ({
                            uri: attribution.web?.uri,
                            title: attribution.web?.title,
                        }))
                        .filter(source => source.uri && source.title);

                    if (sources.length > 0) {
                        sourcesHtml = '<div style="margin-top: 20px; border-top: 1px solid #eee; padding-top: 10px;">';
                        sourcesHtml += '<p style="font-size: 12px; color: #555; margin-bottom: 5px;">출처:</p>';
                        sources.forEach((source, index) => {
                            sourcesHtml += \`<p style="font-size: 12px; margin: 2px 0;"><a href="\${source.uri}" target="_blank" style="color: #007bff; text-decoration: none;">\${source.title}</a></p>\`;
                        });
                        sourcesHtml += '</div>';
                    }
                }

                resultDiv.innerHTML = text + sourcesHtml;

            } else {
                resultDiv.innerHTML = '<span style="color: #dc3545;">예측 결과를 가져오는 데 실패했습니다. 응답 구조를 확인해주세요.</span>';
                console.error("API response missing text content:", result);
            }

        } catch (error) {
            resultDiv.innerHTML = '<span style="color: #dc3545;">API 호출 중 오류 발생: ' + error.message + '</span>';
            console.error("Prediction Error:", error);
        } finally {
            button.disabled = false;
            // 결과가 보이도록 스크롤 이동
            resultDiv.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }


    // ---------------------------------------------
    // 1. 시간별 상세 기록 차트 (simpleChart - 빨간색)
    // ---------------------------------------------

    const ctx = document.getElementById('simpleChart').getContext('2d');
    
    if (chartData.length === 0) {
        console.error("Chart data is empty. Cannot render simpleChart.");
        document.getElementById('simpleChart').parentNode.innerHTML = "<p style='text-align: center; color: #dc3545; padding: 50px; font-size: 16px;'>데이터가 없어 차트를 그릴 수 없습니다.</p>";
    } else {
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: chartLabels,
                datasets: [{
                    label: '기록 값',
                    data: chartData,
                    borderColor: 'rgba(255, 99, 132, 1)',
                    backgroundColor: 'rgba(255, 99, 132, 0.4)', 
                    borderWidth: 3, 
                    tension: 0.4,
                    pointRadius: 4,
                    pointBackgroundColor: 'rgba(255, 99, 132, 1)', 
                    pointHoverRadius: 6,
                    fill: 'start'
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: {
                        type: 'category', 
                        title: { display: true, text: '시간 (HH:MM)', font: { size: 14, weight: 'bold' } },
                        ticks: {
                            maxRotation: 45, 
                            minRotation: 45,
                            autoSkip: true,
                            maxTicksLimit: 25,
                            font: { size: 12 }
                        }
                    },
                    y: {
                        title: { display: true, text: '값', font: { size: 14, weight: 'bold' } },
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
                        text: '시간별 상세 기록 (HH:MM)',
                        font: { size: 18, weight: 'bold' },
                        padding: { top: 10, bottom: 10 }
                    }
                }
            }
        });
    }

    // ---------------------------------------------
    // 2. 일일 집계 차트 (dailyChart - 파란색)
    // ---------------------------------------------
    const dailyCtx = document.getElementById('dailyChart').getContext('2d');

    if (jsDailyValues.length === 0) {
        console.error("Daily chart data is empty. Cannot render dailyChart.");
        document.getElementById('dailyChart').parentNode.innerHTML = "<p style='text-align: center; color: #007bff; padding: 50px; font-size: 16px;'>일일 집계 데이터가 없어 차트를 그릴 수 없습니다.</p>";
    } else {
        new Chart(dailyCtx, {
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
                        ticks: { font: { size: 12 } }
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