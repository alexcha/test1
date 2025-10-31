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
        # 테이블 스타일 및 헤더 정의 (배경색 white로 유지)
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

            # HTML 행 출력 (배경색 white 유지)
            printf "<tr>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; font-weight: bold; color: #333; background-color: white;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; text-align: right; background-color: white; %s\">%s</td>\
            </tr>\n", time_str, current_val_str, color_style, diff_display
        }
        
        print "</tbody></table>";
    }
' result.txt)

# 3. 일별 집계 테이블 생성 (데이터 값 총합 및 전날 대비 변화 포함, 검정색 스타일)
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

        # 테이블 시작 (검정색 테두리)
        print "<table style=\"width: 100%; max-width: 1000px; border-collapse: separate; border-spacing: 0; border: 1px solid #343a40; font-size: 14px; min-width: 300px; border-radius: 8px; overflow: hidden; margin-top: 20px;\">";
        # 테이블 헤더
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
            
            # 🚨 HTML 행 내용을 저장. 날짜 필드에 bold 스타일 없음.
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


# 4. HTML 파일 생성 (index.html)

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
        #chartContainer { 
            margin-bottom: 50px; 
            border: 1px solid #eee; 
            border-radius: 8px; 
            padding: 15px; 
            background: #fff; 
            /* 반응형 높이를 위해 vh 사용 */
            height: 40vh; 
            min-height: 300px; 
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.05);
        }
        h2 { 
            margin-top: 40px; 
            margin-bottom: 15px; 
            text-align: center; 
            color: #dc3545; 
            font-size: 22px; 
            font-weight: 600;
            border-bottom: 2px solid #dc3545; 
            padding-bottom: 10px;
            display: inline-block;
            width: auto;
            margin-left: auto;
            margin-right: auto;
        }
        /* 일별 통계 테이블 헤더 색상 조정 (검정색) */
        .summary-header-black {
            border-bottom-color: #343a40 !important; /* Dark Gray/Black */
            color: #343a40 !important; 
            margin-top: 60px !important;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>데이터 변화 추이</h1>
        <p class="update-time">최근 업데이트 시간: $(tail -n 1 result.txt | awk -F ' : ' '{print $1}')</p>
        
        <!-- 차트 영역 -->
        <div id="chartContainer">
            <canvas id="simpleChart"></canvas>
        </div>
        
        <!-- 🚨 일별 집계 테이블 영역 추가 (상단 배치) -->
        <div style="text-align: center;">
            <h2 class="summary-header-black">일별 마지막 기록 값</h2>
        </div>
        <div>
            ${DAILY_SUMMARY_TABLE}
        </div>

        <!-- 데이터 표 영역 (하단 배치) -->
        <div style="text-align: center;">
            <h2>데이터 기록 (최신순)</h2>
        </div>
        <div>
            ${HTML_TABLE_ROWS}
        </div>
        
    </div>
    
    <script>
    // 🚨 셸 스크립트에서 파싱된 동적 데이터가 여기에 삽입됩니다.
    const chartData = [${JS_VALUES}];
    const chartLabels = [${JS_LABELS}];

    console.log("Chart Data Array:", chartData);
    console.log("Chart Labels Array:", chartLabels);

    const ctx = document.getElementById('simpleChart').getContext('2d');
    
    if (chartData.length === 0) {
        console.error("Chart data is empty. Cannot render chart.");
        document.getElementById('chartContainer').innerHTML = "<p style='text-align: center; color: #dc3545; padding: 50px; font-size: 16px;'>데이터가 없어 차트를 그릴 수 없습니다.</p>";
    } else {
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: chartLabels,
                datasets: [{
                    label: '값 변화 추이',
                    data: chartData,
                    borderColor: 'rgba(255, 99, 132, 1)', 
                    backgroundColor: 'rgba(255, 99, 132, 0.4)', 
                    borderWidth: 3, 
                    tension: 0.5, 
                    pointRadius: 4,
                    pointBackgroundColor: 'rgba(255, 99, 132, 1)', 
                    pointHoverRadius: 6,
                    fill: false 
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
                        grid: {
                            color: 'rgba(0, 0, 0, 0.05)',
                        },
                        ticks: {
                            // Y축 값에 K, M, B 축약 포맷 적용
                            callback: function(value) {
                                if (value === 0) return '0';
                                
                                const absValue = Math.abs(value);
                                let formattedValue;

                                if (absValue >= 1000000000) {
                                    // 10억 이상 (Billion)
                                    formattedValue = (value / 1000000000).toFixed(1).replace(/\.0$/, '') + 'B';
                                } else if (absValue >= 1000000) {
                                    // 100만 이상 (Million)
                                    formattedValue = (value / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
                                } else if (absValue >= 1000) {
                                    // 1천 이상 (Kilo)
                                    formattedValue = (value / 1000).toFixed(1).replace(/\.0$/, '') + 'K';
                                } else {
                                    // 1천 미만은 기존 쉼표 포맷 유지
                                    formattedValue = new Intl.NumberFormat('ko-KR').format(value);
                                }
                                return formattedValue;
                            }
                        }
                    }
                },
                plugins: {
                    legend: {
                        display: false
                    },
                    tooltip: {
                        mode: 'index',
                        intersect: false,
                        bodyFont: { size: 14 },
                        callbacks: {
                            label: function(context) {
                                let label = context.dataset.label || '';
                                if (label) {
                                    label += ': ';
                                }
                                if (context.parsed.y !== null) {
                                    // 툴팁 값은 전체 숫자에 쉼표 포맷 적용
                                    label += new Intl.NumberFormat('ko-KR').format(context.parsed.y);
                                }
                                return label;
                            }
                        }
                    },
                    title: {
                        display: true,
                        text: '값 변화 추이 (Chart.js)',
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