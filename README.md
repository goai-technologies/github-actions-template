# Github Actions Template

## Overview

This repository provides a set of reusable GitHub Actions workflows and templates designed to streamline CI/CD pipelines for various deployment scenarios. It aims to simplify automation for building, testing, and deploying applications using GitHub Actions.

## Directory Structure

- `build-and-push/` - Contains workflow and action files related to building Docker images and pushing them to container registries.
- `check-codepipeline/` - Contains workflows and actions for checking AWS CodePipeline status and integration.
- `check-codeploy/` - Contains workflows and actions for checking AWS CodeDeploy status and integration.

## Included Workflows and Actions

- **Build and Push**: Automates Docker image build and push to registries.
- **Check CodePipeline**: Monitors AWS CodePipeline execution status.
- **Check CodeDeploy**: Monitors AWS CodeDeploy deployment status.

## Usage

1. Copy the desired workflow or action directory into your repository.
2. Customize the workflow YAML files (`*.yml` or `*.yaml`) according to your project requirements.
3. Reference the workflows in your GitHub Actions configuration to automate your CI/CD processes.

## Configuration

Each workflow/action directory contains a YAML file defining the GitHub Actions workflow. Customize parameters such as:

- AWS credentials and region
- Docker image names and tags
- Pipeline and deployment identifiers

## Contributing

Contributions are welcome! Please fork the repository and submit pull requests for improvements or new features.

## License

This project is licensed under the MIT License.

## Contact

For questions or support, please open an issue on GitHub.
