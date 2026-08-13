# Datadog contracts

`dashboard.json`, `slo.json`, `monitors.json`은 Datadog API로 가져오는 기준 구성이다. `DD_API_KEY`, `DD_APP_KEY`는 Secrets Manager `shopport-ENV/datadog`에만 저장한다.

애플리케이션 custom metric 계약:

- `shopport.ai.first_chunk_ms`, `shopport.ai.total_ms`, `shopport.ai.concurrent_streams`
- `shopport.ai.reconnect`, `shopport.quota.denied`
- `shopport.provider.failure`, `shopport.provider.zero_result` with low-cardinality `provider_id`

request ID와 W3C `traceparent`만 상관관계에 사용한다. prompt, 이미지, access/refresh token, provider secret, full outbound URL은 tag, span, log에 기록하지 않는다.

99.9% 월간 availability SLO는 production API의 non-5xx request 비율이다. 예약된 maintenance도 denominator에서 자동 제외하지 않는다.
