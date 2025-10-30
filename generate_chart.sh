#!/bin/bash

# 1. 데이터 파싱: 값(Y축)과 레이블(X축) 분리
# JS_VALUES: 쉼표로 구분된 값
JS_VALUES=$(awk -F ' : ' '{ 
    gsub(/,/, "", $2); 
    if (NR==1) {printf $2} else {printf ", %s", $2} 
}' result.txt | tr -d '\n' | sed 's/^[ \t]*//;s/[ \t]*$//')

# JS_LABELS: 따옴표로 감싸고 쉼표로 구분된 시간
JS_LABELS=$(awk -F ' : ' '{ 
    split($1, time_arr, " "); 
    short_label = time_arr[2] " " time_arr[3]; 
    if (NR==1) {printf "\"%s\"", short_label} else {printf ", \"%s\"", short_label} 
}' result.txt | tr -d '\n' | sed 's/^[ \t]*//;s/[ \t]*$//')

# 2. HTML 파일 생성 (index.html)
# 파일명 변경 및 제목/색상 적용
cat << CHART_END > index.html
<!DOCTYPE html>
<html>
<head>
    <title>No..</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        #chartContainer { width: 90%; max-width: 1000px; margin: auto; }
    </style>
</head>
<body>
    <h1>추이</h1> <p>최근 업데이트 시간: $(tail -n 1 result.txt | awk -F ' : ' '{print $1}')</p>
    <div id="chartContainer">
        <canvas id="simpleChart"></canvas>
    </div>
    
    <script>
    const chartData = [${JS_VALUES}];
    const chartLabels = [${JS_LABELS}];

    const ctx = document.getElementById('simpleChart').getContext('2d');
    
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
                    // 🚨 색상: 붉은 계열
                    borderColor: 'rgba(255, 99, 132, 1)', 
                    backgroundColor: 'rgba(255, 99, 132, 0.2)',
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
