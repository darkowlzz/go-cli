package policy

import (
	"github.com/dnephin/cobra"
	"github.com/storageos/go-api/types"
	"github.com/storageos/go-cli/cli/command"
	"github.com/storageos/go-cli/cli/command/inspect"
)

type inspectOptions struct {
	format   string
	policies []string
}

func newInspectCommand(storageosCli *command.StorageOSCli) *cobra.Command {
	var opt inspectOptions

	cmd := &cobra.Command{
		Use:   "inspect [OPTIONS] [POLICY...]",
		Short: "Display detailed information on one or more polic(y|ies) - if none are specified all policies are inspected (with ID listed)",
		Args:  nil,
		RunE: func(cmd *cobra.Command, args []string) error {
			opt.policies = args

			if len(opt.policies) == 0 {
				return runInspectAll(storageosCli, opt)
			}

			return runInspect(storageosCli, opt)
		},
	}

	cmd.Flags().StringVarP(&opt.format, "format", "f", "", "Format the output using the given Go template")

	return cmd
}

func runInspect(storageosCli *command.StorageOSCli, opt inspectOptions) error {
	client := storageosCli.Client()

	getFunc := func(ref string) (interface{}, []byte, error) {
		i, err := client.Policy(ref)
		return i, nil, err
	}

	return inspect.Inspect(storageosCli.Out(), opt.policies, opt.format, getFunc)
}

func runInspectAll(storageosCli *command.StorageOSCli, opt inspectOptions) error {
	client := storageosCli.Client()

	getListFunc := func() ([]interface{}, []byte, error) {
		policies, err := client.PolicyList(types.ListOptions{})
		intfs := []interface{}{}

		for id, policy := range policies {
			policy := types.PolicyWithID{Policy: policy, ID: id}
			intfs = append(intfs, policy)
		}
		return intfs, nil, err
	}

	return inspect.InspectAll(storageosCli.Out(), opt.format, getListFunc)
}
