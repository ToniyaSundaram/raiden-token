"""
Deploy ReserveToken and DutchAuction on a testnet
"""
import click
from populus import Project
from web3 import Web3
from utils import (
    createWallet,
    check_succesful_tx
)
from simulation import (
    getAuctionFactors,
    auction_simulation
)

multiplier = 10**18


@click.command()
@click.option(
    '--chain',
    default='kovan',
    help='Chain to deploy on: kovan | ropsten | rinkeby | tester | privtest'
)
@click.option(
    '--owner',
    help='Contracts owner, default: web3.eth.accounts[0]'
)
@click.option(
    '--supply',
    default=10000000,
    help='Token contract supply (number of total issued tokens).'
)
@click.option(
    '--price-factor',
    default=6,
    help='Price factor used in auction price calculation.'
)
@click.option(
    '--price-constant',
    default=66,
    help='Price constant used in auction price calculation.'
)
@click.option(
    '--price-points',
    help='2 price points "price1_in_wei,elapsed_seconds1,price2_in_wei,elapsed_seconds2" used to calculate the price factor and constant for the auction price function. Example: "100000000000000000,0,10000000000000000,600"'
)
@click.option(
    '--prealloc-addresses',
    help='Addresses separated by a comma, for preallocating tokens.'
)
@click.option(
    '--prealloc-amounts',
    help='Token amounts separated by a comma, for preallocating tokens.'
)
@click.option(
    '--simulation',
    is_flag=True,
    help='Run auction simulation.'
)
@click.option(
    '--bidders',
    default=10,
    help='Number of bidders. Only if the --simulation flag is set'
)
@click.option(
    '--bids',
    default=10,
    help='Number of bidders. Only if the --simulation flag is set'
)
@click.option(
    '--bid-price',
    default=50000000000000000,
    help='Price per TKN in WEI at which the first bid should start. Only if the --simulation flag is set'
)
@click.option(
    '--bid-interval',
    default=5,
    help='Time interval in seconds between bids. Only if the --simulation flag is set'
)
def main(**kwargs):
    project = Project()

    chain_name = kwargs['chain']
    owner = kwargs['owner']
    supply = kwargs['supply'] * multiplier
    price_factor = kwargs['price_factor']
    price_constant = kwargs['price_constant']
    simulation = kwargs['simulation']
    bidders = int(kwargs['bidders'])
    bid_start_price = int(kwargs['bid_price'])
    bid_interval = kwargs['bid_interval']
    bids_number = int(kwargs['bids'])
    price_points = kwargs['price_points']

    if price_points:
        price_points = price_points.split(',')
        (a, b) = getAuctionFactors(int(price_points[0]), int(price_points[1]), int(price_points[2]), int(price_points[3]), multiplier)
        price_factor = a
        price_constant = b

    print("Make sure {} chain is running, you can connect to it and it is synced, or you'll get timeout".format(chain_name))

    with project.get_chain(chain_name) as chain:
        web3 = chain.web3
        owner = owner or web3.eth.accounts[0]

        # Set preallocations
        if kwargs['prealloc_addresses']:
            prealloc_addresses = kwargs['prealloc_addresses'].split(',')
        else:
            if len(web3.eth.accounts) >= 2:
                prealloc_addresses = web3.eth.accounts[1:3]
            else:
                # Create needed accounts if they don't exist
                prealloc_addresses = []
                priv_keys = []
                for i in range(0, 2):
                    priv_key, address = createWallet()
                    priv_keys.append(priv_key)
                    prealloc_addresses.append('0x' + address)
                print('Preallocations will be sent to the following addresses:')
                print(prealloc_addresses)
                print('Preallocation addresses private keys: ', priv_keys)

        if kwargs['prealloc_amounts']:
            prealloc_amounts = kwargs['prealloc_amounts'].split(',')
        else:
            prealloc_amounts = [
                200000 * multiplier,
                800000 * multiplier
            ]

        print("Web3 provider is", web3.currentProvider)
        assert owner, "Make sure owner account is created"
        print('Owner', owner)
        print('Preallocation addresses & amounts in WEI', prealloc_addresses, prealloc_amounts)
        print('Auction price factor:', price_factor)
        print('Auction price constant:', price_constant)

        # Load Populus contract proxy classes
        Auction = chain.provider.get_contract_factory('DutchAuction')
        Token = chain.provider.get_contract_factory('ReserveToken')

        # Deploy Auction
        txhash = Auction.deploy(transaction={"from": owner}, args=[price_factor, price_constant])
        print("Deploying auction, tx hash is", txhash)
        receipt = check_succesful_tx(web3, txhash)
        auction_address = receipt["contractAddress"]
        print("Auction contract address is", auction_address)

        # Deploy token
        txhash = Token.deploy(transaction={"from": owner}, args=[
            auction_address,
            supply,
            prealloc_addresses,
            prealloc_amounts
        ])
        print("Deploying token, tx hash is", txhash)
        receipt = check_succesful_tx(web3, txhash)
        token_address = receipt["contractAddress"]
        print("Token contract address is", token_address)

        # Make contracts aware of each other
        print("Initializing contracts")
        auction = Auction(address=auction_address)
        token = Token(address=token_address)

        txhash = auction.transact({"from": owner}).setup(token_address)
        check_succesful_tx(web3, txhash)

        # Do some contract reads to see everything looks ok
        print("Token total supply is", token.call().totalSupply(), 'Tei = ', int(token.call().totalSupply() / multiplier), 'TKN')
        print("Auction price at elapsed = 0 is", auction.call().price(), 'WEI', web3.fromWei(auction.call().price(), 'ether'), 'ETH')

        # Start simulation if --simulation flag is set
        if simulation:
            print('Starting simulation setup for', bidders, 'bidders')
            bidder_addresses = []
            bidder_addresses = web3.eth.accounts[3:(bidders + 3)]
            print('Creating more bidder accounts:', bidders -  len(bidder_addresses), 'accounts')
            for i in range(len(bidder_addresses), bidders):
                address = web3.personal.newAccount('0')
                bidder_addresses.append(address)

            print('Simulating', len(bidder_addresses), 'bidders', bidder_addresses)
            print('Bids will start at', bid_start_price, 'WEI = ', web3.fromWei(bid_start_price, 'ether'), 'ETH  / TKN')
            auction_simulation(web3, token, auction, owner, bidder_addresses, bids_number, bid_interval, bid_start_price)


if __name__ == "__main__":
    main()