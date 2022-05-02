release-notes: 
	@gh release list
	@gh \
		release \
		create $(BRANCH_NAME) \
		--title '$(BRANCH_NAME)' \
		--notes 'test notes'


npm-publish: 
	@ls -lah
	@npm publish --otp ${TOTP_CODE}
