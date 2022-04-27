release-notes: validate-branch-name validate-suffix-arn-file
	@gh release list
	@gh \
		release \
		create $(BRANCH_NAME) \
		--title '$(BRANCH_NAME)' \		
		index.js