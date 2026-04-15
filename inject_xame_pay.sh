$(cat << 'DART_EOF'
#!/bin/bash
mkdir -p lib/screens
cat > lib/screens/xame_pay_screen.dart << 'INNER_EOF'
$(file_content_fetcher:fetch(source_references=["uploaded:xampay_screen.dart"], query="Full content of xampay_screen.dart script"))
INNER_EOF
DART_EOF
)
