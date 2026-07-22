# eryu — 自托管网易云音乐服务（零外部依赖，纯 Python stdlib）
FROM python:3.12-slim

WORKDIR /app

# 复制服务端代码 + 前端
COPY server/eryu.py /app/
COPY server/analyze_song.py /app/
COPY client/ /app/client/

# 数据目录
RUN mkdir -p /app/data/music_cache

# 启动脚本：从环境变量写入配置 → Supabase 同步（数据+凭证）→ 启动 eryu
RUN echo '#!/bin/bash\n\
if [ -n "$MUSIC_U" ]; then\n\
  echo "MUSIC_U=$MUSIC_U" > /app/.netease_cred\n\
  echo "[eryu] MUSIC_U configured"\n\
else\n\
  echo "[eryu] WARNING: MUSIC_U not set — search may not work"\n\
fi\n\
if [ -n "$ERYU_AUTH_TOKEN" ]; then\n\
  echo "$ERYU_AUTH_TOKEN" > /app/.secret\n\
  echo "[eryu] Auth token configured from env"\n\
fi\n\
# Supabase 存档同步（每10分钟上传 + 退出时上传）\n\
if [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_SERVICE_ROLE_KEY" ] && [ -n "$SUPABASE_BUCKET" ]; then\n\
  echo "[eryu] Supabase sync configured"\n\
  # ① 先从 Supabase 恢复凭证文件（.secret / .netease_cred）\n\
  for f in .netease_cred .secret; do\n\
    curl -s -o /app/$f -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" "$SUPABASE_URL/storage/v1/object/$SUPABASE_BUCKET/$f" 2>/dev/null && echo "[sync] ⬇ $f" || true\n\
  done\n\
  # ② 再恢复数据文件\n\
  for f in music_data.json music_memory.json music_playlist.json music_remote.json; do\n\
    curl -s -o /app/data/$f -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" "$SUPABASE_URL/storage/v1/object/$SUPABASE_BUCKET/$f" 2>/dev/null && echo "[sync] ⬇ $f" || true\n\
  done\n\
  # ③ 后台定时上传（每10分钟，包含凭证 + 数据）\n\
  (while true; do sleep 600; for f in /app/data/*.json /app/.netease_cred /app/.secret; do\n\
    [ -f "$f" ] && curl -s -X POST -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" --data-binary "@$f" "$SUPABASE_URL/storage/v1/object/$SUPABASE_BUCKET/$(basename $f)" > /dev/null 2>&1 && echo "[sync] ⬆ $(basename $f)"\n\
  done; done) &\n\
  # ④ 退出时上传（也包含凭证）\n\
  trap "for f in /app/data/*.json /app/.netease_cred /app/.secret; do [ -f \"$f\" ] && curl -s -X POST -H \"Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY\" -H \"apikey: $SUPABASE_SERVICE_ROLE_KEY\" --data-binary \"@$f\" \"$SUPABASE_URL/storage/v1/object/$SUPABASE_BUCKET/$(basename $f)\" > /dev/null 2>&1; done; echo '[sync] exit upload done'" EXIT\n\
fi\n\
# 内置自唤醒：每 9 分钟 self-ping，防止 Render 休眠\n\
(while true; do sleep 540; wget -q -O /dev/null http://localhost:9090/health || true; done) &\n\
exec python /app/eryu.py\n\
' > /app/start.sh && chmod +x /app/start.sh

EXPOSE 9090
ENV PORT=9090
ENV SUPABASE_URL=https://mwymafgqtnyepfqhujqv.supabase.co
ENV SUPABASE_BUCKET=eryu-data
ENV ERYU_AUTH_TOKEN=lloromannic-eryu-token-2026-♡music♡
CMD ["/app/start.sh"]
