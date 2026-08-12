<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!--
  短時間の連続リクエストを防止する。
  ユーザーごとに適用し、バースト的なリクエストを平滑化する。
-->
<SpikeArrest name="SA-SpikeArrest">
  <Identifier ref="jwt.DJ-DecodeIapJwt.claim.email"/>
  <Rate>${spike_arrest_rate}</Rate>
</SpikeArrest>
