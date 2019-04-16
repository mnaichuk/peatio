describe Ethereum1::Blockchain do
  context :features do
    it 'defaults' do
      blockchain1 = Ethereum1::Blockchain.new
      expect(blockchain1.features).to eq Ethereum1::Blockchain::DEFAULT_FEATURES
    end

    it 'override defaults' do
      blockchain2 = Ethereum1::Blockchain.new(supports_cash_addr_format: true)
      expect(blockchain2.features[:supports_cash_addr_format]).to be_truthy
    end

    it 'custom feautures' do
      blockchain3 = Ethereum1::Blockchain.new(custom_feature: :custom)
      expect(blockchain3.features.keys).to contain_exactly(:supports_cash_addr_format, :case_sensitive)
    end
  end

  context :configure do
    let(:blockchain) { Ethereum1::Blockchain.new }
    it 'default settings' do
      expect(blockchain.settings).to eq({})
    end

    it 'currencies and server configuration' do
      currencies = Currency.where(type: :coin).first(2).map(&:to_blockchain_api_settings)
      settings = { server: 'http://127.0.0.1:18332',
                   currencies: currencies,
                   something: :custom }
      blockchain.configure(settings)
      expect(blockchain.settings).to eq(settings.slice(*Peatio::Blockchain::Abstract::SUPPORTED_SETTINGS))
    end
  end

  context :latest_block_number do
    around do |example|
      WebMock.disable_net_connect!
      example.run
      WebMock.allow_net_connect!
    end

    let(:server) { 'http://127.0.0.1:8545' }
    let(:blockchain) do
      Ethereum1::Blockchain.new.tap { |b| b.configure(server: server) }
    end

    it 'returns latest block number' do
      block_number = 1489174

      stub_request(:post, 'http://127.0.0.1:8545')
        .with(body: { jsonrpc: '2.0',
                      id: 1,
                      method: :eth_blockNumber,
                      params:  [] }.to_json)
        .to_return(body: { result: block_number,
                           error:  nil,
                           id:     1 }.to_json)

      expect(blockchain.latest_block_number).to eq(block_number)
    end

    it 'raises error if there is error in response body' do
      stub_request(:post, 'http://127.0.0.1:8545')
        .with(body: { jsonrpc: '2.0',
                      id: 1,
                      method: :eth_blockNumber,
                      params:  [] }.to_json)
        .to_return(body: { result: nil,
                           error:  { code: -32601, message: 'Method not found' },
                           id:     nil }.to_json)

      expect{ blockchain.latest_block_number }.to raise_error(Ethereum1::Client::ResponseError)
    end
  end

  context :fetch_block! do
    around do |example|
      WebMock.disable_net_connect!
      example.run
      WebMock.allow_net_connect!
    end

    let(:block_file_name) { '2621839-2621843.json' }

    let(:block_data) do
      Rails.root.join('spec', 'resources', 'ethereum-data', 'rinkeby', block_file_name)
        .yield_self { |file_path| File.open(file_path) }
        .yield_self { |file| JSON.load(file) }
    end

    let(:transaction_receipt_data) do
      Rails.root.join('spec', 'resources', 'ethereum-data', 'rinkeby/transaction-receipts', block_file_name)
          .yield_self { |file_path| File.open(file_path) }
          .yield_self { |file| JSON.load(file) }
    end

    let(:start_block)   { block_data.first['result']['number'].hex }
    let(:latest_block)  { block_data.last['result']['number'].hex }

    def request_block_body(block_height)
      { jsonrpc: '2.0',
        id: 1,
        method: :eth_getBlockByNumber,
        params:  [block_height, true]
      }.to_json
    end

    # def request_block_body(block_hash)
    #   { jsonrpc: '2.0',
    #     method:  :getblock,
    #     params:  [block_hash, 2]
    #   }.to_json
    # end

    before do
      block_data.each do |blk|
        # stub get_block_hash
        stub_request(:post, endpoint)
          .with(body: request_block_body(blk['result']['number']))
          .to_return(body: blk.to_json )

        # # stub get_block
        # stub_request(:post, endpoint)
        #   .with(body: request_block_body(blk['result']['hash']))
        #   .to_return(body: blk.to_json)
      end
    end

    let(:server) { 'http://127.0.0.1:8545' }
    let(:endpoint) { 'http://127.0.0.1:8545' }
    let(:blockchain) do
      Ethereum1::Blockchain.new.tap { |b| b.configure(server: server) }
    end

    xit 'ii' do
      blockchain.fetch_block!(start_block)
    end
  end

  context :build_transaction do

    let(:tx_file_name) { '1858591d8ce638c37d5fcd92b9b33ee96be1b950e593cf0cbf45e6bfb1ad8a22.json' }

    let(:tx_hash) do
      Rails.root.join('spec', 'resources', 'bitcoin-data', tx_file_name)
        .yield_self { |file_path| File.open(file_path) }
        .yield_self { |file| JSON.load(file) }
    end
    let(:expected_transactions) do
      [{:hash=>"1858591d8ce638c37d5fcd92b9b33ee96be1b950e593cf0cbf45e6bfb1ad8a22",
        :txout=>0,
        :to_address=>"mg4KVGerD3rYricWC8CoBaayDp1YCKMfvL",
        :amount=>0.325e0,
        :currency_id=>currency.id},
       {:hash=>"1858591d8ce638c37d5fcd92b9b33ee96be1b950e593cf0cbf45e6bfb1ad8a22",
        :txout=>1,
        :to_address=>"mqaBwWDjJCE2Egsf6pfysgD5ZBrfsP7NkA",
        :amount=>0.1964466932e2,
        :currency_id=>currency.id}]
    end

    let(:currency) do
      Currency.find_by(id: :btc)
    end

    let(:blockchain) do
      Bitcoin::Blockchain.new.tap { |b| b.configure(currencies: [currency.to_blockchain_api_settings]) }
    end

    it 'builds formatted transactions for passed transaction' do
      expect(blockchain.send(:build_transaction, tx_hash)).to contain_exactly(*expected_transactions)
    end

    context 'multiple currencies' do
      let(:expected_transactions) do
        [{:hash=>"1858591d8ce638c37d5fcd92b9b33ee96be1b950e593cf0cbf45e6bfb1ad8a22",
          :txout=>0,
          :to_address=>"mg4KVGerD3rYricWC8CoBaayDp1YCKMfvL",
          :amount=>0.325e0,
          :currency_id=>currency1.id},
         {:hash=>"1858591d8ce638c37d5fcd92b9b33ee96be1b950e593cf0cbf45e6bfb1ad8a22",
          :txout=>1,
          :to_address=>"mqaBwWDjJCE2Egsf6pfysgD5ZBrfsP7NkA",
          :amount=>0.1964466932e2,
          :currency_id=>currency1.id},
         {:hash=>"1858591d8ce638c37d5fcd92b9b33ee96be1b950e593cf0cbf45e6bfb1ad8a22",
          :txout=>0,
          :to_address=>"mg4KVGerD3rYricWC8CoBaayDp1YCKMfvL",
          :amount=>0.325e0,
          :currency_id=>currency2.id},
         {:hash=>"1858591d8ce638c37d5fcd92b9b33ee96be1b950e593cf0cbf45e6bfb1ad8a22",
          :txout=>1,
          :to_address=>"mqaBwWDjJCE2Egsf6pfysgD5ZBrfsP7NkA",
          :amount=>0.1964466932e2,
          :currency_id=>currency2.id}]
      end

      let(:currency1) do
        Currency.find_by(id: :btc)
      end

      let(:currency2) do
        Currency.find_by(id: :btc)
      end

      let(:blockchain) do
        Bitcoin::Blockchain.new.tap do |b|
          b.configure(currencies: [currency1.to_blockchain_api_settings, currency2.to_blockchain_api_settings])
        end
      end

      it 'builds formatted transactions for passed transaction per each currency' do
        expect(blockchain.send(:build_transaction, tx_hash)).to contain_exactly(*expected_transactions)
      end
    end
  end
end
