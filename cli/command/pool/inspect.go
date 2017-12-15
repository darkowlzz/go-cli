package pool

import (
	"github.com/dnephin/cobra"
	"github.com/storageos/go-api/types"
	"github.com/storageos/go-cli/cli/command"
	"github.com/storageos/go-cli/cli/command/inspect"
)

type inspectOptions struct {
	format string
	names  []string
}

func newInspectCommand(storageosCli *command.StorageOSCli) *cobra.Command {
	var opt inspectOptions

	cmd := &cobra.Command{
		Use:   "inspect [OPTIONS] [POOL...]",
		Short: "Display detailed information on one or more capacity pools - if none are specified all pools are inspected",
		Args:  nil,
		RunE: func(cmd *cobra.Command, args []string) error {
			opt.names = args

			if len(opt.names) == 0 {
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

	getFunc := func(name string) (interface{}, []byte, error) {
		i, err := client.Pool(name)
		return i, nil, err
	}

	return inspect.Inspect(storageosCli.Out(), opt.names, opt.format, getFunc)
}

func runInspectAll(storageosCli *command.StorageOSCli, opt inspectOptions) error {
	client := storageosCli.Client()

	getListFunc := func() ([]interface{}, []byte, error) {
		pools, err := client.PoolList(types.ListOptions{})
		intfs := make([]interface{}, len(pools))
		for i, p := range pools {
			intfs[i] = p
		}
		return intfs, nil, err
	}

	return inspect.InspectAll(storageosCli.Out(), opt.format, getListFunc)
}
