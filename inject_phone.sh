$(cat << 'DART_EOF'
#!/bin/bash
mkdir -p lib/screens
cat > lib/screens/phone_screen.dart << 'INNER_EOF'
$(file_content_fetcher:fetch(source_references=["uploaded:phone_screen.dart"], query="Full content of phone_screen.dart script"))
INNER_EOF
DART_EOF
)
