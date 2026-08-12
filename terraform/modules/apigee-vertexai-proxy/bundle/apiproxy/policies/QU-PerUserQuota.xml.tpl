<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!--
  ユーザーごとのリクエスト数クォータ。
  IAP JWT から取得した email をキーにカウントする。
-->
<Quota name="QU-PerUserQuota">
  <Identifier ref="jwt.DJ-DecodeIapJwt.claim.email"/>
  <Allow count="${quota_limit}"/>
  <Interval>${quota_interval}</Interval>
  <TimeUnit>${quota_time_unit}</TimeUnit>
  <Distributed>true</Distributed>
  <Synchronous>true</Synchronous>
</Quota>
