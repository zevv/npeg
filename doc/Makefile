
npeg.html: ../README.md header.md Makefile
	cat header.md > tmp.md
	grep -v "!\[" ../README.md >> tmp.md
	asciidoctor -o npeg.html tmp.md
	rm tmp.md
