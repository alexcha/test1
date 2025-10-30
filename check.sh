#!/bin/bash

# 1. Markdown 표 헤더 생성
MARKDOWN_TABLE="
# 스트리밍 이맨트 추이

최근 업데이트 시간: $(tail -n 1 result.txt | awk -F ' : ' '{print $1}')

| 시간 (KST) | 값 |
| :--- | ---: |
"
# result.txt 파일의 모든 데이터를 Markdown 표 행으로 변환
TABLE_ROWS=$(awk -F ' : ' '{
    timestamp = $1
    value = $2
    # 쉼표를 제거하지 않고 유지하여 가독성 높임
    printf "| %s | %s |\n", timestamp, value
}' result.txt)

# 2. Markdown 파일 생성 (README.md)
# 기존 README.md가 있다면 덮어씁니다.
echo "$MARKDOWN_TABLE" > README.md
echo "$TABLE_ROWS" >> README.md
