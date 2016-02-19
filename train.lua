--require('mobdebug').start()
require 'dp'
require 'rnn'
require 'image'
--require 'datasets/flickr8k'
--requikwardre 'lib/propagatorcaptioner.lua'
--require 'lib/evaluatorcaptioner'
--require 'lib/optimizercaptioner'
--require 'lib/perplexitycaptioner'
--require 'lib/VRClassRewardCaptioner'

-------------------------------------------
--- command line parameters
-------------------------------------------
cmd = torch.CmdLine()
cmd:text()
cmd:text('Options')

--- training options ---
cmd:option('--learningRate', 0.0001, 'learning rate at t=0')
cmd:option('--minLR', 0.00001, 'minimum learning rate')
cmd:option('--saturateEpoch', 800, 'epoch at which linear decayed LR will reach minLR')
cmd:option('--momentum', 0.9, 'momentum')
cmd:option('--maxOutNorm', -1, 'max norm each layers output neuron weights')
cmd:option('--cutoffNorm', -1, 'max l2-norm of contatenation of all gradParam tensors')
cmd:option('--batchSize', 1, 'number of examples per batch')
cmd:option('--cuda', false, 'use CUDA')
cmd:option('--gpuid', 1, 'sets the device (GPU) to use')
cmd:option('--maxEpoch', 5000, 'maximum number of epochs to run')
cmd:option('--maxTries', 20, 'maximum number of epochs to try to find a better local minima for early-stopping')
cmd:option('--transfer', 'ReLU', 'activation function')
cmd:option('--uniform', 0.1, 'initialize parameters using uniform distribution between -uniform and uniform. -1 means default initialization')
cmd:option('--xpPath', '', 'path to a previously saved model')
cmd:option('--progress', false, 'print progress bar')
cmd:option('--silent', false, 'dont print anything to stdout')

--- reinforce ---
cmd:option('--rewardScale', 0, "scale of positive reward (negative is 0)")
cmd:option('--unitPixels', 127, "the locator unit (1,1) maps to pixels (13,13), or (-1,-1) maps to (-13,-13)")
cmd:option('--locatorStd', 0.11, 'stdev of gaussian location sampler (between 0 and 1) (low values may cause NaNs)')
cmd:option('--stochastic', false, 'Reinforce modules forward inputs stochastically during evaluation')

---  dataset info  ---
cmd:option('-dataset', 'flickr8k', 'which dataset to train. flickr8k, flickr30k or mscoco')
cmd:option('--trainEpochSize', -1, 'number of train examples seen between each epoch')
cmd:option('--validEpochSize', -1, 'number of valid examples used for early stopping and cross-validation') 
cmd:option('--noTest', false, 'dont propagate through the test set')
cmd:option('--overwrite', false, 'overwrite checkpoint')

---  model info  ---
cmd:option('--glimpseHiddenSize', 128, 'size of glimpse hidden layer')
cmd:option('--glimpsePatchSize', 8, 'size of glimpse patch at highest res (height = width)')
cmd:option('--glimpseScale', 2, 'scale of successive patches w.r.t. original input image')
cmd:option('--glimpseDepth', 3, 'number of concatenated downscaled patches')
cmd:option('--locatorHiddenSize', 128, 'size of locator hidden layer')
cmd:option('--imageHiddenSize', 256, 'size of hidden layer combining glimpse and locator hiddens')

-- activate function
cmd:option('--transfer', 'ReLU', 'activation function')

-- recurrent layer
cmd:option('--rho',17)
cmd:option('--hiddenSize', 256)
cmd:option('--dropout', false, 'apply dropout on hidden neurons')

local opt = cmd:parse(arg)

-------------------------------------------
--- setup your dataset
-------------------------------------------
ds = dp['Flickr8k']()

------------------------------------------
---------------   Model   ----------------
------------------------------------------

--- input is {img,{x,y}}, img is bchw, batch x 3 x 256 x 256

--- 1. location sensor
locationSensor = nn.Sequential()
locationSensor:add(nn.SelectTable(2)) -- select {x,y}
locationSensor:add(nn.Linear(2,opt.locatorHiddenSize))
locationSensor:add(nn[opt.transfer]())

--- 2.glimpse sensor
glimpseSensor = nn.Sequential()
glimpseSensor:add(nn.DontCast(nn.SpatialGlimpse(opt.glimpsePatchSize, opt.glimpseDepth, opt.glimpseScale):float(), true))
glimpseSensor:add(nn.Collapse(3))
glimpseSensor:add(nn.Linear(ds:imageSize('c')*opt.glimpsePatchSize^2*opt.glimpseDepth, opt.glimpseHiddenSize))
glimpseSensor:add(nn[opt.transfer]())

--- 3.glimpse
glimpse = nn.Sequential()
glimpse:add(nn.ConcatTable():add(locationSensor):add(glimpseSensor))
glimpse:add(nn.JoinTable(1,1))
glimpse:add(nn.Linear(opt.locatorHiddenSize+opt.glimpseHiddenSize, opt.imageHiddenSize))
glimpse:add(nn[opt.transfer]())
glimpse:add(nn.Linear(opt.imageHiddenSize, opt.hiddenSize))

--- 4. recurrent layer
recurrent = nn.Linear(opt.hiddenSize, opt.hiddenSize)
--recurrent = nn.FastLSTM(opt.hiddenSize, opt.hiddenSize)

--- 5. recurrent neural network
rnn = nn.Recurrent(opt.hiddenSize, glimpse, recurrent, nn[opt.transfer](), 99999)

--- 6. action: sample {x,y} using reinforce
locator = nn.Sequential()
locator:add(nn.Linear(opt.hiddenSize,2))
locator:add(nn.HardTanh())
locator:add(nn.ReinforceNormal(2*opt.locatorStd, opt.stochastic)) -- sample from normal, uses REINFORCE learning rule
locator:add(nn.HardTanh()) -- bounds sample between -1 and 1
locator:add(nn.MulConstant(opt.unitPixels*2/ds:imageSize("h")))

attention = nn.RecurrentAttention(rnn, locator, opt.rho, {opt.hiddenSize}, opt.cuda)

-- model is a reinforcement learning agent
agent = nn.Sequential()
agent:add(nn.Convert(ds:ioShapes(), 'bchw'))
agent:add(attention)

-- classifier :
--agent:add(nn.SelectTable(-1)) -- since we need to use outputs of every timestep in RNN, rather than only use the output of the last timestep, thus omit the SelectTable(-1) operation
--agent:add(nn.Linear(opt.hiddenSize, #ds:classes()))
--agent:add(nn.LogSoftMax())
-- #TODO: checkout nn.Sequencser usage
agent:add(nn.Sequencer(nn.Linear(opt.hiddenSize, #ds:classes())))
agent:add(nn.Sequencer(nn.LogSoftMax())) 

-- add the baseline reward predictor
seq = nn.Sequential()
seq:add(nn.Constant(1,1))
seq:add(nn.Add(1))
concat = nn.ConcatTable():add(nn.Identity()):add(seq)
concat2 = nn.ConcatTable():add(nn.Identity()):add(concat)

-- output will be : {classpred, {classpred, basereward}}
--agent:add(concat2)
agent:add(nn.Sequencer(concat2))

if opt.uniform > 0 then
   for k,param in ipairs(agent:parameters()) do
      param:uniform(-opt.uniform, opt.uniform)
   end
end

--[[Propagators]]--
opt.decayFactor = (opt.minLR - opt.learningRate)/opt.saturateEpoch

train = dp.OptimizerCaptioner{
   loss = nn.ParallelCriterion(true)
      :add(nn.ModuleCriterion(nn.SequencerCriterion(nn.ClassNLLCriterion())), nil, nn.Sequencer(nn.Convert()))
      --:add(nn.ModuleCriterion(nn.SequencerCriterion(nn.VRClassRewardCaptioner(agent, opt.rewardScale))), nil, nn.Sequencer(nn.Convert()))
      :add(nn.ModuleCriterion(nn.VRClassRewardCaptioner(agent, opt.rewardScale)), nil, nn.Convert())
   ,
   epoch_callback = function(model, report) -- called every epoch
      if report.epoch > 0 then
         opt.learningRate = opt.learningRate + opt.decayFactor
         opt.learningRate = math.max(opt.minLR, opt.learningRate)
         if not opt.silent then
            print("learningRate", opt.learningRate)
         end
      end
   end,
   callback = function(model, report)       
      if opt.cutoffNorm > 0 then
         local norm = model:gradParamClip(opt.cutoffNorm) -- affects gradParams
         opt.meanNorm = opt.meanNorm and (opt.meanNorm*0.9 + norm*0.1) or norm
         if opt.lastEpoch < report.epoch and not opt.silent then
            print("mean gradParam norm", opt.meanNorm)
         end
      end
      model:updateGradParameters(opt.momentum) -- affects gradParams
      model:updateParameters(opt.learningRate) -- affects params
      model:maxParamNorm(opt.maxOutNorm) -- affects params
      model:zeroGradParameters() -- affects gradParams 
   end,
   feedback = dp.PerplexityCaptioner(),
   sampler = dp.ShuffleSampler{
      epoch_size = opt.trainEpochSize, batch_size = opt.batchSize
   },
   progress = opt.progress,
   _cuda = opt.cuda
}


valid = dp.EvaluatorCaptioner{
   feedback = dp.PerplexityCaptioner(),
   sampler = dp.Sampler{epoch_size = opt.validEpochSize, batch_size = opt.batchSize},
   progress = opt.progress,
   _cuda = opt.cuda
}
if not opt.noTest then
   tester = dp.EvaluatorCaptioner{
      feedback = dp.PerplexityCaptioner(),
      sampler = dp.Sampler{batch_size = opt.batchSize},
      _cuda = opt.cuda
   }
end

--[[Experiment]]--
xp = dp.Experiment{
   model = agent,
   optimizer = train,
   validator = valid,
   tester = tester,
   observer = {
      --ad,
      --dp.FileLogger(),
      dp.EarlyStopper{
         max_epochs = opt.maxTries, 
         error_report={'validator','feedback','perplexity','ppl'},
         maximize = false
      }
   },
   random_seed = os.time(),
   max_epoch = opt.maxEpoch
}

--[[GPU or CPU]]--
if opt.cuda then
   require "cutorch"
   require "cunn"
   cutorch.setDevice(opt.gpuid) 
   xp:cuda()
end

xp:verbose(not opt.silent)
if not opt.silent then
   print"Agent :"
   print(agent)
end

xp.opt = opt

xp:run(ds)

