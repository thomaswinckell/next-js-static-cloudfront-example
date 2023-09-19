region?=eu-west-1
stackName?=my-stack-name
certificateStackName?=my-stack-name-certificate
domain?=my-domain.com

# Function to get stack output value given a key
define get_stack_output
$(shell aws cloudformation describe-stacks \
		--region $(region) \
		--stack-name $(stackName) \
		--output json \
		--query 'Stacks[0].Outputs[?OutputKey==`$(1)`].OutputValue' \
		--output text)
endef

# Function to get certificate stack output value given a key
define get_certificate_stack_output
$(shell aws cloudformation describe-stacks \
		--region us-east-1 \
		--stack-name $(certificateStackName) \
		--output json \
		--query 'Stacks[0].Outputs[?OutputKey==`$(1)`].OutputValue' \
		--output text)
endef

# Build the app
build:
	npm ci
	npm run build

# Deploy the certificate stack
deploy-certificate:
	aws cloudformation deploy --template-file ./cfn/certificate.yaml --stack-name=$(certificateStackName) --region=us-east-1 --no-fail-on-empty-changeset \
		--parameter-overrides \
 		 "DomainName=$(domain)"

# Deploy the main stack
deploy:
	aws cloudformation deploy --template-file ./cfn/template.yaml --stack-name $(stackName) --region=$(region) --no-fail-on-empty-changeset \
 		--parameter-overrides \
 		 "DomainName=$(domain)" \
 		 "AcmCertificate=$(call get_certificate_stack_output, AcmCertificateArn)"

# Upload build to S3
upload-s3:
	$(eval bucket := $(call get_stack_output, NextBucket))
	# sync next static folder
	aws s3 sync ./out/_next s3://$(bucket)/_next/ \
 		--metadata-directive REPLACE \
        --cache-control max-age=31536000,public
	# copy assets (excluding html and next folder)
	aws s3 cp ./out s3://$(bucket)/ \
		--recursive \
		--exclude "_next/*" \
		--exclude "*.html" \
		--metadata-directive REPLACE \
		--cache-control max-age=0,no-cache,no-store,must-revalidate
	# copy html files without .html extension
	cd ./out && find * -type f -name "*.html" -exec sh -c 'aws s3 cp "./$$0" s3://$(bucket)/"$${0%.html}" --metadata-directive REPLACE --content-type text/html --cache-control max-age=0,no-cache,no-store,must-revalidate' {} \;