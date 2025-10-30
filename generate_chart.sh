#!/bin/bash

# 1. 데이터 파싱: 값(Y축)과 레이블(X축) 분리

# JS_VALUES: 값들을 쉼표로 구분하여 문자열로 생성하고, 트레일링 공백(trailing space) 제거
JS_VALUES=$(awk -F ' : ' '{ 
    gsub(/,/, "", $2); 
    if (NR==1) {printf $2} else {printf ", %s", $2} 
}' result.txt | tr -d '\n' | sed 's/^[ \t]*//;s/[ \t]*$//') # 🚨 줄바꿈 및 공백 제거

# JS_LABELS: 시간 레이블을 따옴표로 감싸고 쉼표로 구분하여 문자열로 생성하고, 트레일링 공백(trailing space) 제거
JS_LABELS=$(awk -F ' : ' '{ 
    split($1, time_arr, " "); 
    short_label = time_arr[2] " " time_arr[3]; 
    if (NR==1) {printf "\"%s\"", short_label} else {printf ", \"%s\"", short_label} 
}' result.txt | tr -d '\n' | sed 's/^[ \t]*//;s/[ \t]*$//') # 🚨 줄바꿈 및 공백 제거

# 2. HTML 파일 생성
cat << CHART_END > chart.html
<!DOCTYPE html>
<html>
<head>
    <title>스트리밍 데이터 차트</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        #chartContainer { width: 90%; max-width: 1000px; margin: auto; }
    </style>
</head>
<body>
    <h1>스트리밍 데이터 변화 추이 (KST)</h1>
    <p>최근 업데이트 시간: $(tail -n 1 result.txt | awk -F ' : ' '{print $1}')</p>
    <div id="chartContainer">
        <canvas id="simpleChart"></canvas>
    </div>
    
    <script>
    // 🚨 Bash 변수에는 줄바꿈이나 불필요한 공백이 포함되어 있지 않으므로 안전하게 삽입
    const chartData = [${JS_VALUES}];
    const chartLabels = [${JS_LABELS}];

    const ctx = document.getElementById('simpleChart').getContext('2d');
    
    // 🚨 데이터가 비어있는지 확인하는 방어 코드 추가
    if (chartData.length === 0) {
        console.error("Chart data is empty. Cannot render chart.");
        document.getElementById('chartContainer').innerHTML = "<p>데이터가 없어 차트를 그릴 수 없습니다.</p>";
    } else {
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: chartLabels,
                datasets: [{
                    label: '값 변화 추이',
                    data: chartData,
                    borderColor: 'rgba(75, 192, 192, 1)',
                    backgroundColor: 'rgba(75, 192, 192, 0.2)',
                    borderWidth: 2,
                    tension: 0.1,
                    pointRadius: 3
                }]
            },
            options: {
                responsive: true,
                scales: {
                    x: {
                        type: 'category', 
                        title: { display: true, text: '시간 (HH:MM KST)' }
                    },
                    y: {
                        title: { display: true, text: '값' },
                        beginAtZero: false,
                        ticks: {
                            callback: function(value) {
                                return value.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
                            }
                        }
                    }
                },
                plugins: {
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                let label = context.dataset.label || '';
                                if (label) {
                                    label += ': ';
                                }
                                if (context.parsed.y !== null) {
                                    label += context.parsed.y.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
                                }
                                return label;
                            }
                        }
                    }
                }
            }
        });
    }
    </script>
</body>
</html>
CHART_END
