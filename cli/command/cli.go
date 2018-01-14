package command

import (
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"

	"github.com/dnephin/cobra"

	api "github.com/storageos/go-api"
	cliconfig "github.com/storageos/go-cli/cli/config"
	"github.com/storageos/go-cli/cli/config/configfile"
	cliflags "github.com/storageos/go-cli/cli/flags"
	"github.com/storageos/go-cli/cli/opts"
)

// Streams is an interface which exposes the standard input and output streams
type Streams interface {
	In() *InStream
	Out() *OutStream
	Err() io.Writer
}

// Cli represents the storageos command line client.
type Cli interface {
	Client() api.Client
	Out() *OutStream
	Err() io.Writer
	In() *InStream
	ConfigFile() *configfile.ConfigFile
}

// StorageOSCli is an instance the storageos command line client.
// Instances of the client can be returned from NewStorageOSCli.
type StorageOSCli struct {
	configFile      *configfile.ConfigFile
	hosts           []string
	username        string
	password        string
	in              *InStream
	out             *OutStream
	err             io.Writer
	keyFile         string
	client          *api.Client
	hasExperimental bool
	defaultVersion  string
}

// GetHosts returns the client's endpoints
func (cli *StorageOSCli) GetHosts() []string {
	return cli.hosts
}

// GetHosts returns the client's username
func (cli *StorageOSCli) GetUsername() string {
	return cli.username
}

// GetPassword returns the client's password
func (cli *StorageOSCli) GetPassword() string {
	return cli.password
}

// HasExperimental returns true if experimental features are accessible.
func (cli *StorageOSCli) HasExperimental() bool {
	return cli.hasExperimental
}

// DefaultVersion returns api.defaultVersion of DOCKER_API_VERSION if specified.
func (cli *StorageOSCli) DefaultVersion() string {
	return cli.defaultVersion
}

// Client returns the APIClient
func (cli *StorageOSCli) Client() *api.Client {
	return cli.client
}

// Out returns the writer used for stdout
func (cli *StorageOSCli) Out() *OutStream {
	return cli.out
}

// Err returns the writer used for stderr
func (cli *StorageOSCli) Err() io.Writer {
	return cli.err
}

// In returns the reader used for stdin
func (cli *StorageOSCli) In() *InStream {
	return cli.in
}

// ShowHelp shows the command help.
func (cli *StorageOSCli) ShowHelp(cmd *cobra.Command, args []string) error {
	cmd.SetOutput(cli.err)
	cmd.HelpFunc()(cmd, args)
	return nil
}

// ConfigFile returns the ConfigFile
func (cli *StorageOSCli) ConfigFile() *configfile.ConfigFile {
	return cli.configFile
}

// Initialize the dockerCli runs initialization that must happen after command
// line flags are parsed.
func (cli *StorageOSCli) Initialize(opt *cliflags.ClientOptions) error {
	cli.configFile = LoadDefaultConfigFile(cli.err)

	host, err := getServerHost(opt.Common.Hosts, opt.Common.TLS)
	if err != nil {
		return err
	}
	cli.hosts = []string{host}

	client, err := NewAPIClientFromFlags(host, opt.Common, cli.configFile)
	if err != nil {
		return err
	}
	cli.client = client

	cli.defaultVersion = cli.client.ClientVersion()

	return nil
}

// NewStorageOSCli returns a StorageOSCli instance with IO output and error streams set by in, out and err.
func NewStorageOSCli(in io.ReadCloser, out, err io.Writer) *StorageOSCli {
	return &StorageOSCli{in: NewInStream(in), out: NewOutStream(out), err: err}
}

// LoadDefaultConfigFile attempts to load the default config file and returns
// an initialized ConfigFile struct if none is found.
func LoadDefaultConfigFile(err io.Writer) *configfile.ConfigFile {
	configFile, e := cliconfig.Load(cliconfig.Dir())
	if e != nil {
		fmt.Fprintf(err, "WARNING: Error loading config file:%v\n", e)
	}
	// if !configFile.ContainsAuth() {
	// 	credentials.DetectDefaultStore(configFile)
	// }
	return configFile
}

// NewAPIClientFromFlags creates a new APIClient from command line flags
func NewAPIClientFromFlags(host string, opt *cliflags.CommonOptions, configFile *configfile.ConfigFile) (*api.Client, error) {

	if host == "" {
		return &api.Client{}, fmt.Errorf("STORAGEOS_HOST evironemnt variable not set")
	}

	verStr := api.DefaultVersionStr
	if tmpStr := os.Getenv(cliconfig.EnvStorageosAPIVersion); tmpStr != "" {
		verStr = tmpStr
	}

	client, err := api.NewVersionedClient(host, verStr)
	if err != nil {
		return &api.Client{}, err
	}

	var username string
	var password string

	p, err := url.Parse(host)
	if err != nil {
		username = os.Getenv(cliconfig.EnvStorageosUsername)
		password = os.Getenv(cliconfig.EnvStorageosPassword)
	} else {
		port := p.Port()
		if port == "" {
			port = api.DefaultPort
		}

		credHost := fmt.Sprintf("%s:%s", p.Hostname(), port)
		username, password, err = configFile.CredentialsStore.GetCredentials(credHost)
		if err != nil {
			username = os.Getenv(cliconfig.EnvStorageosUsername)
			password = os.Getenv(cliconfig.EnvStorageosPassword)
		}
	}

	if opt.Username != "" {
		username = opt.Username
	}
	if opt.Password != "" {
		password = opt.Password
	}

	if username != "" && password != "" {
		client.SetAuth(username, password)
	}

	return client, nil
}

func getServerHost(hosts []string, tls bool) (host string, err error) {
	switch len(hosts) {
	case 0:
		host = os.Getenv(cliconfig.EnvStorageOSHost)
	case 1:
		host = hosts[0]
	default:
		return "", errors.New("Please specify only one -H")
	}

	host, err = opts.ParseHost(tls, host)
	return
}

// Standard alias definitions
var (
	CreateAliases  = []string{"c"}
	InspectAliases = []string{"i"}
	ListAliases    = []string{"list"}
	UpdateAliases  = []string{"u"}
	RemoveAliases  = []string{"remove"}
	HealthAliases  = []string{"h"}
)

func WithAlias(c *cobra.Command, aliases ...string) *cobra.Command {
	c.Aliases = append(c.Aliases, aliases...)
	return c
}
